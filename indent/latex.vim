" Indent extension for the VimTeXtended plugin.
" Author: Marcel Simader (marcel0simader@gmail.com)
" Date: 09.12.2021
" (c) Marcel Simader 2021

" load tex syntax
runtime indent/tex.vim

" acts as include guard
if exists("b:vimtex_did_indent")
    finish
endif
let b:vimtex_did_indent = 1

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ INDENT EXTENSIONS ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

" unset item indent
"              set                      unset
"   ------------------------------------------------------
"       \begin{itemize}            \begin{itemize}
"         \item blablabla            \item blablabla
"           bla bla bla              bla bla bla
"         \item blablabla            \item blablabla
"           bla bla bla              bla bla bla
"       \end{itemize}              \end{itemize}
" (taken from /usr/share/vim81/indent/tex.vim)
let b:tex_indent_items = 0

