" Syntax extensions for the ViT plugin.
" Author: Marcel Simader (marcel0simader@gmail.com)
" Date: 08.12.2021
" (c) Marcel Simader 2021

" acts as include guard
if exists("b:current_syntax") || (exists('g:vit_enable') && !g:vit_enable)
    finish
endif

" load default LaTeX syntax
runtime syntax/tex.vim

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ SYNTAX EXTENSIONS ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

" add some common math environments
call TexNewMathZone("SA", "equation", 1)
call TexNewMathZone("SB", "gather", 1)
call TexNewMathZone("SC", "align", 1)
call TexNewMathZone("SD", "alignat", 1)
call TexNewMathZone("SE", "multline", 1)

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ CLEANUP ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

let b:current_syntax = "latex"

