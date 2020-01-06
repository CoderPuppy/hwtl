(define even (lambda (n) (if (= n 0) true (odd (pred n)))))
(define odd (lambda (n) (if (= n 0) false (even (pred n)))))
