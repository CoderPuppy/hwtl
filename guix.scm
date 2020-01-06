(use-modules
	(guix packages)
	(guix download)
	(guix utils)
	(guix profiles)
	(guix build-system gnu)
	((guix licenses) #:prefix license:)
	(gnu packages lua)
	(ice-9 optargs))

(define-public luajit-52compat-gc64 (package
	(inherit luajit)
	(name "luajit-52compat-gc64")
	(arguments (let ((prev (package-arguments luajit)))
		(let-keywords prev #t ((make-flags (list)))
			`(,@prev #:make-flags (cons "XCFLAGS= -DLUAJIT_ENABLE_LUA52COMPAT -DLUAJIT_ENABLE_GC64" ,make-flags)))))))

(define (make-lua-penlight name lua lua-filesystem)
	(package
		(name name)
		(version "1.6.0")
		(source (origin
			(method url-fetch)
			(uri (string-append
				"https://github.com/stevedonovan/"
				"Penlight/archive/" version ".tar.gz"))
			(file-name (string-append name "-" version ".tar.gz"))
			(sha256 (base32 "1c2lfgi27qyk6m3kpww766gxakmdg9m9jilpaz4r9app2jix0lm5"))))
		(build-system gnu-build-system)
		(arguments `(
			#:phases (modify-phases %standard-phases
				(delete 'configure)
				(delete 'build)
				(delete 'check)
				; (replace 'check (lambda _
				; 	(setenv "LUA_PATH" "lua/?.lua;;")
				; 	(setenv "LUA_CPATH" (string-append
				; 		(assoc-ref %build-inputs "lua-filesystem") "/lib/lua/"
				; 		,(version-major+minor (package-version lua)) "/?.so;;"))
				; 	(invoke "lua" "run.lua")))
				(replace 'install (lambda _
					(define share-lua (string-append
						(assoc-ref %outputs "out") "/share/lua/"
						,(version-major+minor (package-version lua))))
					(mkdir-p share-lua)
					(copy-recursively "lua" share-lua))))))
		(inputs `(("lua" ,lua)))
		(propagated-inputs `(("lua-filesystem" ,lua-filesystem)))
		(home-page "https://stevedonovan.github.io/penlight/index.html")
		(synopsis "Lua utility libraries loosley based on the Python standard libraries")
		(description "Penlight is a set of pure Lua libraries for making it easier to work with common tasks like
iterating over directories, reading configuration files and the like. Provides functional operations
on tables and sequences.")
		(license license:expat)))

(define lua5.1-penlight (make-lua-penlight "lua5.1-penlight" lua-5.1 lua5.1-filesystem))

(define (make-lua-utf8 name lua)
	(package
		(name name)
		(version "0.1.1")
		(source (origin
			(method url-fetch)
			(uri (string-append
				"https://github.com/starwing/"
				"luautf8/archive/" version ".tar.gz"))
			(file-name (string-append name "-" version ".tar.gz"))
			(sha256 (base32 "1kkdp7gr230f8jalkgdy3p9d8kb9jjhd7rj4pbzj8kbi47zpmvp3"))))
		(build-system gnu-build-system)
		(arguments `(
			#:phases (modify-phases %standard-phases
				(delete 'configure)
				(replace 'build (lambda* (#:key inputs #:allow-other-keys)
					(define gcc (string-append (assoc-ref inputs "gcc") "/bin/gcc"))
					(invoke gcc
						(string-append "-I" (assoc-ref inputs "lua") "/include")
						(string-append "-L" (assoc-ref inputs "lua") "/lib")
						"-shared" "-fPIC"
						"lutf8lib.c" "-olua-utf8.so")))
				(delete 'check)
				; (replace 'check (lambda _
				; 	(setenv "LUA_PATH" "lua/?.lua;;")
				; 	(setenv "LUA_CPATH" (string-append
				; 		(assoc-ref %build-inputs "lua-filesystem") "/lib/lua/"
				; 		,(version-major+minor (package-version lua)) "/?.so;;"))
				; 	(invoke "lua" "run.lua")))
				(replace 'install (lambda _
					(install-file "lua-utf8.so" (string-append
						(assoc-ref %outputs "out") "/lib/lua/"
						,(version-major+minor (package-version lua)))))))))
		(inputs `(("lua" ,lua)))
		(home-page "https://github.com/starwing/luautf8")
		(synopsis "A UTF-8 support module for Lua")
		(description "luautf8 adds UTF-8 support to Lua. It's compatible with Lua \"string\" module.")
		(license license:expat)))

(define lua5.1-utf8 (make-lua-utf8 "lua5.1-utf8" lua-5.1))

(packages->manifest (list
	luajit-52compat-gc64
	lua5.1-penlight
	lua5.1-utf8))
