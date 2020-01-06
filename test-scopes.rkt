#lang racket

(require racket/function)
(require threading)

(struct scope (desc))
(struct id (name scopes) #:transparent)
(struct binding (id handler))

(define (binding-name binding) (id-name (binding-id binding)))
(define (binding-scopes binding) (id-scopes (binding-id binding)))

(define (visit sexp #:pre-fn [pre-fn identity] #:post-fn [post-fn identity])
	(set! sexp (pre-fn sexp))
	(post-fn (cond
		[(list? sexp)
			(map
				(lambda (sexp) (visit sexp #:pre-fn pre-fn #:post-fn post-fn))
				sexp)]
		[(id? sexp) sexp]
		[(string? sexp) sexp]
		[(symbol? sexp) sexp]
		[(number? sexp) sexp]
		[else (error (format "bad: ~a" sexp))])))

(define (add-scope sexp scope)
	(visit sexp #:post-fn (lambda (sexp)
		(cond
			[(id? sexp) (id (id-name sexp) (set-add (id-scopes sexp) scope))]
			[else sexp]))))

(define (find-telescope sexp #:telescope [telescope '()])
	(cond
		[(list? sexp)
			(find-telescope (car sexp)
				#:telescope (cons (cons 'app (cdr sexp)) telescope))]
		[else (cons sexp telescope)]))

(define (find-winning-binding bindings)
	(match
		(for/fold
			([heads (list)])
			([binding bindings])
			(if (findf (lambda (head) (subset? (binding-scopes binding) (binding-scopes head))) heads)
				heads
				(cons binding (filter (lambda (head) (not (subset? (binding-scopes head) (binding-scopes binding)))) heads))))
		[(list binding) binding]
		[bindings (error (format "multiple bindings: ~a" bindings))]))

(define (expand-telescope-part head part)
	(match part
		[(cons 'app args)
			(list* '#%app head (map expand args))]))

(define (expand-telescope head telescope)
	(foldl
		(lambda (part head) (expand-telescope-part head part))
		head telescope))

(define (expand sexp)
	(match-define (cons head telescope) (find-telescope sexp))
	(cond
		[(id? head)
		 ((binding-handler (find-winning-binding (hash-ref bindings (id-name head)))) telescope)]
		[(string? head) (expand-telescope `(#%str-lit ,head) telescope)]
		[(number? head) (expand-telescope `(#%num-lit ,head) telescope)]
		[else (error (format "bad head: ~a" head))]))

(define bindings (make-hash))
(define (add-binding id handler)
	(define b (binding id handler))
	(set-add! (hash-ref! bindings (id-name id) mutable-set) b)
	b)

(define prog `((lambda args
	(define a 1)
	(print a))))
(set! prog (visit prog #:post-fn (lambda (sexp)
	(cond
		[(symbol? sexp) (id sexp (set))]
		[else sexp]))))

(define top-level (scope "top-level"))
(add-binding (id 'lambda (set top-level)) (match-lambda [(list-rest (list-rest 'app (and args-id (? id?)) body) telescope)
	(define lam-s (scope (format "lambda: args = ~a" (id-name args-id))))
	(set! args-id (id (id-name args-id) (set-add (id-scopes args-id) lam-s)))
	(define args-b (add-binding args-id (lambda (telescope)
		(list '#%var args-b))))
	(expand-telescope
		(list* '#%lambda args-b (map
			(lambda (sexp)
				(expand (add-scope sexp lam-s)))
			body))
		telescope)]))
(add-binding (id 'define (set top-level)) (match-lambda [(list-rest (list 'app (and var-id (? id?)) val) telescope)
	(define var-b (add-binding var-id (lambda (telescope)
		(list '#%var var-b))))
	(expand-telescope
		(list '#%define var-b (expand val))
		telescope)]))
(add-binding (id 'print (set top-level)) (lambda (telescope)
	(expand-telescope '(#%builtin print) telescope)))
(set! prog (add-scope prog top-level))

(expand prog)
