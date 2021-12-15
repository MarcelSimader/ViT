" Set filetype for VimTeXtended.
" Author: Marcel Simader (marcel0simader@gmail.com)
" Date: 09.12.2021
" (c) Marcel Simader 2021

" acts as include guard
if exists("g:vimtex_did_filetypedetect")
    finish
endif
let g:vimtex_did_filetypedetect = 1

augroup VimTeXDetectFileType
    autocmd!
    autocmd BufNewFile,BufRead *.tex,*.latex set filetype=latex
augroup END

