
all:
	make clean src/langlex.c src/lang
	mv src/lang verif_spec
clean:
	rm -f src/langlex.c lang.tab.c lang.output verif_spec
# Foreach file ./tests/*.prog, run the compiler. Break on error.
test:
	make all
	@for f in tests/*.prog; do \
		echo "Testing $$f"; \
		./verif_spec  $$f; \
		if [ $$? -ne 0 ]; then \
			echo "Error in $$f"; \
			break; \
		fi; \
	done
	
	
