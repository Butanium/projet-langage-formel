
all:
	make clean bison/langlex.c bison/lang
clean:
	rm -f bison/lang bison/langlex.c lang.tab.c lang.output 
# Foreach file ./examples/*.prog, run the compiler. Break on error.
test:
	make all
	@for f in examples/*.prog; do \
		echo "Testing $$f"; \
		./bison/lang $$f; \
		if [ $$? -ne 0 ]; then \
			echo "Error in $$f"; \
			break; \
		fi; \
	done
	
	
