(define pure succ (lambda (n) (+ n 1)))
(define pure pred (lambda (n) (- n 1)))
(define pure - (lambda (h . t) (+ h (* -1 (+ (unpack t))))))
(define pure fib (lambda (n)
	(if (<= n 1)
		n
		(+ (fib (- n 1)) (fib (- n 2)))
	)
))
(log! (fib 10))

(define pure odd (lambda (n)
	(if (= n 0)
		false
		(even (pred n))
	)
))
(define pure even (lambda (n)
	(if (= n 0)
		true
		(odd (pred n))
	)
))

(log! '(a b))

; (while true
; 	(log! "hi")
; 	(if true
; 		(log! "a")
; 		(log! "b")
; 	)
; )

(define imm hello\ world 1)
