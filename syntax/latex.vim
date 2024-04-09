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

" ~~~~~~~~~~~~~~~~~~~~ Extension for Knitr ~~~~~~~~~~~~~~~~~~~~

if exists('g:vit_enable_knitr') && g:vit_enable_knitr
    unlet b:current_syntax
    syntax include @Rlang syntax/r.vim
    syntax region ViTKnitrReg matchgroup=Delimiter start=/<<[[:ident:]-='", ]*>>=/ end=/\\\@<!@/
                \ contains=@Rlang containedin=TOP,@texFoldGroup
    syntax sync match ViTKnitrRegSync groupthere ViTKnitrReg /<<[[:ident:]-='", ]*>>=/
    syntax sync match ViTKnitrRegSync grouphere NONE /\\\@<!@/
    syntax region ViTKnitrSexpr matchgroup=Delimiter start=/\\Sexpr{/ end=/}/
                \ contains=@Rlang containedin=TOP,@texFoldGroup
endif

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ CLEANUP ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

let b:current_syntax = "latex"

