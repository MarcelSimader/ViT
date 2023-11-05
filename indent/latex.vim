" Indent functions for the ViT plugin.
" Author: Marcel Simader (marcel0simader@gmail.com)
" Date: 05.11.2023
" (c) Marcel Simader 2021

let s:cpo_save = &cpo
set cpo&vim

" Acts as include guard and optional off switch
if exists("b:did_indent") || (exists('g:vit_enable') && !g:vit_enable)
    finish
endif

if !exists('g:tex_indent_items')
    let g:tex_indent_items = 0
endif
if !exists('g:tex_noindent_env')
    let g:tex_noindent_env = 'verbatim\|document'
endif
let g:tex_noindent_env .= '\|frame'

" load default LaTeX indent
runtime indent/tex.vim

let b:did_indent = 1

let &cpo = s:cpo_save
unlet s:cpo_save

