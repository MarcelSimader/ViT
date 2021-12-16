" Syntax extensions for the ViT plugin.
" Author: Marcel Simader (marcel0simader@gmail.com)
" Date: 08.12.2021
" (c) Marcel Simader 2021

" load default LaTeX syntax
runtime syntax/tex.vim

" acts as include guard
if exists("b:vit_did_syntax")
    finish
endif
let b:vit_did_syntax = 1

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ SYNTAX EXTENSIONS ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

" only show bold and italic conceal chars
let b:tex_conceal = 'b'

" add some common math environments
call TexNewMathZone("SA", "equation", 1)
call TexNewMathZone("SB", "gather", 1)
call TexNewMathZone("SC", "align", 1)
call TexNewMathZone("SD", "alignat", 1)
call TexNewMathZone("SE", "multline", 1)

