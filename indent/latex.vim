" Indent functions for the ViT plugin.
" Author: Marcel Simader (marcel0simader@gmail.com)
" Date: 05.11.2023
" (c) Marcel Simader 2021

" Only define the function once
if exists("b:did_indent")
    finish
endif

let g:tex_indent_items = 0
let g:tex_noindent_env += ['frame']

" load default LaTeX indent
runtime indent/tex.vim

let b:did_indent = 1

