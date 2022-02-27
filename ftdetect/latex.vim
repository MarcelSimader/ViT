" Set filetype for ViT.
" Author: Marcel Simader (marcel0simader@gmail.com)
" Date: 09.12.2021
" (c) Marcel Simader 2021

" acts as include guard
if exists("g:vit_did_ftdetect")
    finish
endif
let g:vit_did_ftdetect = 1

autocmd BufNewFile,BufRead *.tex,*.latex
            \ if !exists('g:vit_enable') || g:vit_enable | set filetype=latex | endif

