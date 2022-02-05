" Main ViT filetype plugin file (ft=latex).
" Author: Marcel Simader (marcel0simader@gmail.com)
" Date: 28.11.2021
" (c) Marcel Simader 2021

" acts as include guard
if exists("b:did_ftplugin")
    finish
endif

" Start with LaTeX (ft=tex). This will also define b:did_ftplugin
runtime ftplugin/tex.vim

" set cpoptions as per :h usr_41
let s:save_cpo = &cpo
set cpo&vim

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ OPTIONS ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

" set undo options
" TODO: does not work currently?
let b:undo_ftplugin +=
    \ '| setlocal conceallevel< completefunc< completeopt<'
    \.'| unlet b:indentLine_enabled'

" ~~~~~~~~~~ definitely important for function of script
" set option to the above function
setlocal completefunc=vit#CompleteFunc

" ~~~~~~~~~~ not important for function of script, but a good default
" set conceal level
setlocal conceallevel=0
" completion options
setlocal completeopt=menuone,noselect
" we have to disable indentline here as this
" would just break conceallevel
let b:indentLine_enabled = 0

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ KEYMAPS ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

" Automatically insert second X and move in the middle X<Cursor>X
for s:char in g:vit_autosurround_chars
    if len(s:char) == 2
        execute 'inoremap <buffer> '.s:char[0].' '.s:char[0].s:char[1].'<C-O>h'
    endif
endfor
unlet s:char

" quick compiling
nnoremap <buffer> " :ViTCompile<CR>
nnoremap <buffer> ! :ViTCompile!<CR>

" map \ to open autocomplete and write \
imap <buffer> <BSlash> \<C-X><C-U>
" map vim completion to <ViT><C-Space> and <ViT><Space>
execute 'inoremap <buffer> '.g:vit_leader.'<Space> <C-X><C-U>'
execute 'inoremap <buffer> '.repeat(g:vit_leader, 2).' <C-X><C-U>'

" cursor move
inoremap <buffer> <S-Tab> <C-O>:call vit#SmartMoveCursorRight()<CR>

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ COMMANDS ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

command -buffer -bang ViTCompile call vit#Compile(expand('%:p'), expand('%:p:h'), '<bang>')

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ AUTOCOMMANDS ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

" auto compiling
augroup ViTCompile
    autocmd!
    autocmd BufWritePost <buffer> :ViTCompile!
    autocmd CursorMoved <buffer> :call vit#CompileSignHover()
augroup END

" automatic completion-insert detection, triggering
" the command execution
augroup ViTCompletionDetection
    autocmd!
    autocmd BufWritePost <buffer> :call vit#ScanNewCommands()
    autocmd CompleteDone <buffer> :call vit#CompletionDetection()
augroup END

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ STATUSLINE ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

if exists('*airline#add_statusline_func')
    " airline is installed
    if !exists('*ViTAirline')
        function ViTAirline(...)
            if &ft == 'latex'
                let w:airline_section_c = airline#section#create_left(
                            \ ['file', '%{vit#CurrentTeXEnv()}'])
            endif
        endfunction
        call airline#add_statusline_func('ViTAirline')
    endif
else
    " regular statusline
    setlocal statusline=%f\ \|\ %{vit#CurrentTeXEnv()}
endif

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ TEMPLATE DEFINITIONS ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

let s:_ = g:vit_leader

" ~~~~~~~~~~~~~~~~~~~~ general ~~~~~~~~~~~~~~~~~~~~

" ~~~~~~~~~~ text mode
call vit#NewTemplate('ViTProblem',   s:_.'p', 1, 0, [4], 0, [g:vit_comment_line, g:vit_comment_line, g:vit_comment_line, '\problem', ''],                    [])
call vit#NewTemplate('ViTProblemnr', s:_.'P', 1, 0, [5], 0, [g:vit_comment_line, g:vit_comment_line, g:vit_comment_line, '\setproblem{#1}', '\problem', ''], [], 1, ['Number: '])

" ~~~~~~~~~~ text envs
call vit#NewTemplate('ViTEnv',          '<C-E>', 0, 1, [1, 5], 4, ['\begin{#1}'],                                               ['\end{#1}'], 1, ['Name: '])
call vit#NewTemplate('ViTEnum',         s:_.'e', 0, 1, [1, 5], 4, ['\begin{enumerate}'],                                        ['\end{enumerate}'])
call vit#NewTemplate('ViTEnumLeft',     s:_.'E', 0, 1, [1, 5], 4, ['\begin{enumerate}[leftmargin=*,align=left]'],               ['\end{enumerate}'])
call vit#NewTemplate('ViTAlphEnum',     s:_.'l', 0, 1, [1, 5], 4, ['\begin{enumerate}[label=\alph*)]'],                         ['\end{enumerate}'])
call vit#NewTemplate('ViTAlphEnumLeft', s:_.'L', 0, 1, [1, 5], 4, ['\begin{enumerate}[label=\alph*),leftmargin=*,align=left]'], ['\end{enumerate}'])
call vit#NewTemplate('ViTCenter',       s:_.'c', 0, 1, [1, 5], 4, ['\begin{center}'],                                           ['\end{center}'])
call vit#NewTemplate('ViTTabular',      s:_.'t', 0, 1, [1, 5], 4, ['\begin{tabular}{#1}'],                                      ['\end{tabular}'], 1, ['Columns: '])

" ~~~~~~~~~~ math envs
call vit#NewTemplate('ViTEquation', s:_.'q', 0, 1, [1, 5], 4, ['\begin{equation*}'],    ['\end{equation*}'])
call vit#NewTemplate('ViTGather',   s:_.'g', 0, 1, [1, 5], 4, ['\begin{gather*}'],      ['\end{gather*}'])
call vit#NewTemplate('ViTAlign',    s:_.'a', 0, 1, [1, 5], 4, ['\begin{align*}'],       ['\end{align*}'])
call vit#NewTemplate('ViTAlignAt',  s:_.'A', 0, 1, [1, 5], 4, ['\begin{alignat*}{#1}'], ['\end{alignat*}'], 1, ['Columns: '])
call vit#NewTemplate('ViTProof',    s:_.'r', 0, 1, [1, 5], 4, ['\begin{proof}'],        ['\end{proof}'])
call vit#NewTemplate('ViTMatrix',   s:_.'m', 0, 1, [1, 5], 4, ['\begin{matrix}{#1}'],   ['\end{matrix}'], 1, ['Columns: '])

" ~~~~~~~~~~~~~~~~~~~~ inline ~~~~~~~~~~~~~~~~~~~~

call vit#NewTemplate('ViTMathMode',    s:_.'$',    1, 1, [0, 1],  0, ['$'],            ['$'])
call vit#NewTemplate('ViTParentheses', s:_.'1',    1, 1, [0, 7],  0, ['\left( '],      [' \right)'])
call vit#NewTemplate('ViTBrackets',    s:_.'2',    1, 1, [0, 7],  0, ['\left[ '],      [' \right]'])
call vit#NewTemplate('ViTBraces',      s:_.'3',    1, 1, [0, 8],  0, ['\left\{ '],     [' \right\}'])
call vit#NewTemplate('ViTBars',        s:_.'4',    1, 1, [0, 7],  0, ['\left| '],      [' \right|'])
call vit#NewTemplate('ViTOverbrace',   s:_.'<F1>', 1, 1, [0, 11], 0, ['\overbrace{'],  ['}^{}'])
call vit#NewTemplate('ViTUnderbrace',  s:_.'<F2>', 1, 1, [0, 12], 0, ['\underbrace{'], ['}_{}'])
call vit#NewTemplate('ViTBoxed',       s:_.'<F3>', 1, 1, [0, 7],  0, ['\boxed{'],      ['}'])
call vit#NewTemplate('ViTFrac', '', 1, 1, [0, 6], 0, ['\frac{'],  ['}{}'])
call vit#NewTemplate('ViTSqrt', '', 1, 1, [0, 6], 0, ['\sqrt{'],  ['}'])
call vit#NewTemplate('ViTRoot', '', 1, 1, [0, 6], 0, ['\sqrt['],  [']{}'])
call vit#NewTemplate('ViTSum',  '', 1, 1, [0, 6], 0, ['\sum_{'],  ['}^{}'])
call vit#NewTemplate('ViTInt',  '', 1, 1, [0, 6], 0, ['\int_{'],  ['}^{}'])
call vit#NewTemplate('ViTProd', '', 1, 1, [0, 7], 0, ['\prod_{'], ['}^{}'])
call vit#NewTemplate('ViTLim',  '', 1, 1, [0, 6], 0, ['\lim_{'],  ['}'])
call vit#NewTemplate('ViTSup',  '', 1, 1, [0, 6], 0, ['\sup_{'],  ['}'])
call vit#NewTemplate('ViTInf',  '', 1, 1, [0, 6], 0, ['\inf_{'],  ['}'])

unlet s:_

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ CLEANUP ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

" reset cpoptions as per :h usr_41
let &cpo = s:save_cpo
unlet s:save_cpo

