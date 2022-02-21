# Author: Marcel Simader (marcel0simader@gmail.com)
# Date: 20.02.2022
# (c) Marcel Simader 2022

PYTHON_PATH = /usr/include/python3.9

GCC = gcc
GCC_FLAGS = -Os -I $(PYTHON_PATH) -l$(notdir $(PYTHON_PATH)) \
	    -lpthread -lm -lutil -ldl
CYTHON = cython
CYTHON_FLAGS = --embed -3

.PHONY: all
all: scan_latex_sources

scan_latex_sources: scan_latex_sources.c
	$(GCC) $^ -o $@ $(GCC_FLAGS)

scan_latex_sources.c: scan_latex_sources.py
	$(CYTHON) $(CYTHON_FLAGS) $^ -o $@

.PHONY: clean
clean:
	rm scan_latex_sources.c scan_latex_sources

