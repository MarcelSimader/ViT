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

let s:buf = bufname()

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
setlocal completeopt=menuone,noinsert,noselect
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
    autocmd InsertCharPre <buffer> :if pumvisible() | call feedkeys("\<C-X>\<C-U>") | endif
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

" ~~~~~~~~~~ text
call vit#NewTemplate('ViTEnv',          'latex', '<C-E>', 0, 1, [1, 5], 4, ['\begin{#1}'],                                               ['\end{#1}'], 1, ['Name: '])
call vit#NewTemplate('ViTEnum',         'latex', s:_.'e', 0, 1, [1, 5], 4, ['\begin{enumerate}'],                                        ['\end{enumerate}'])
call vit#NewTemplate('ViTEnumLeft',     'latex', s:_.'E', 0, 1, [1, 5], 4, ['\begin{enumerate}[leftmargin=*,align=left]'],               ['\end{enumerate}'])
call vit#NewTemplate('ViTAlphEnum',     'latex', s:_.'l', 0, 1, [1, 5], 4, ['\begin{enumerate}[label=\alph*)]'],                         ['\end{enumerate}'])
call vit#NewTemplate('ViTAlphEnumLeft', 'latex', s:_.'L', 0, 1, [1, 5], 4, ['\begin{enumerate}[label=\alph*),leftmargin=*,align=left]'], ['\end{enumerate}'])
call vit#NewTemplate('ViTCenter',       'latex', s:_.'c', 0, 1, [1, 5], 4, ['\begin{center}'],                                           ['\end{center}'])
call vit#NewTemplate('ViTTabular',      'latex', s:_.'t', 0, 1, [1, 5], 4, ['\begin{tabular}{#1}'],                                      ['\end{tabular}'], 1, ['Columns: '])

call vit#NewTemplate('ViTSection',       'latex', s:_.'s',   0, 1, [3], 0, ['\section{#1}',       '\label{sec:#/\s/-/1}'], [''], 1, ['Name: '])
call vit#NewTemplate('ViTSubSection',    'latex', s:_.'ss',  0, 1, [3], 0, ['\subsection{#1}',    '\label{sec:#/\s/-/1}'], [''], 1, ['Name: '])
call vit#NewTemplate('ViTSubSubSection', 'latex', s:_.'sss', 0, 1, [3], 0, ['\subsubsection{#1}', '\label{sec:#/\s/-/1}'], [''], 1, ['Name: '])
call vit#NewTemplate('ViTParagraph',     'latex', s:_.'p',   0, 1, [3], 0, ['\paragraph{#1}',     '\label{sec:#/\s/-/1}'], [''], 1, ['Name: '])
call vit#NewTemplate('ViTSubParagraph',  'latex', s:_.'pp',  0, 1, [3], 0, ['\subparagraph{#1}',  '\label{sec:#/\s/-/1}'], [''], 1, ['Name: '])

" ~~~~~~~~~~ math
call vit#NewTemplate('ViTEquation', 'latex', s:_.'q', 0, 1, [1, 5], 4, ['\begin{equation*}'],    ['\end{equation*}'])
call vit#NewTemplate('ViTGather',   'latex', s:_.'g', 0, 1, [1, 5], 4, ['\begin{gather*}'],      ['\end{gather*}'])
call vit#NewTemplate('ViTAlign',    'latex', s:_.'a', 0, 1, [1, 5], 4, ['\begin{align*}'],       ['\end{align*}'])
call vit#NewTemplate('ViTAlignAt',  'latex', s:_.'A', 0, 1, [1, 5], 4, ['\begin{alignat*}{#1}'], ['\end{alignat*}'], 1, ['Columns: '])
call vit#NewTemplate('ViTProof',    'latex', s:_.'r', 0, 1, [1, 5], 4, ['\begin{proof}'],        ['\end{proof}'])
call vit#NewTemplate('ViTMatrix',   'latex', s:_.'m', 0, 1, [1, 5], 4, ['\begin{matrix}{#1}'],   ['\end{matrix}'], 1, ['Columns: '])

" ~~~~~~~~~~~~~~~~~~~~ inline ~~~~~~~~~~~~~~~~~~~~

call vit#NewTemplate('ViTMathMode',    'latex', s:_.'$',    1, 1, [0, 1],  0, ['$'],            ['$'])
call vit#NewTemplate('ViTParentheses', 'latex', s:_.'1',    1, 1, [0, 7],  0, ['\left( '],      [' \right)'])
call vit#NewTemplate('ViTBrackets',    'latex', s:_.'2',    1, 1, [0, 7],  0, ['\left[ '],      [' \right]'])
call vit#NewTemplate('ViTBraces',      'latex', s:_.'3',    1, 1, [0, 8],  0, ['\left\{ '],     [' \right\}'])
call vit#NewTemplate('ViTBars',        'latex', s:_.'4',    1, 1, [0, 7],  0, ['\left| '],      [' \right|'])
call vit#NewTemplate('ViTOverbrace',   'latex', s:_.'<F1>', 1, 1, [0, 11], 0, ['\overbrace{'],  ['}^{}'])
call vit#NewTemplate('ViTUnderbrace',  'latex', s:_.'<F2>', 1, 1, [0, 12], 0, ['\underbrace{'], ['}_{}'])
call vit#NewTemplate('ViTBoxed',       'latex', s:_.'<F3>', 1, 1, [0, 7],  0, ['\boxed{'],      ['}'])
call vit#NewTemplate('ViTFrac', 'latex', '', 1, 1, [0, 6], 0, ['\frac{'],  ['}{}'])
call vit#NewTemplate('ViTSqrt', 'latex', '', 1, 1, [0, 6], 0, ['\sqrt{'],  ['}'])
call vit#NewTemplate('ViTRoot', 'latex', '', 1, 1, [0, 6], 0, ['\sqrt['],  [']{}'])
call vit#NewTemplate('ViTSum',  'latex', '', 1, 1, [0, 6], 0, ['\sum_{'],  ['}^{}'])
call vit#NewTemplate('ViTInt',  'latex', '', 1, 1, [0, 6], 0, ['\int_{'],  ['}^{}'])
call vit#NewTemplate('ViTProd', 'latex', '', 1, 1, [0, 7], 0, ['\prod_{'], ['}^{}'])
call vit#NewTemplate('ViTLim',  'latex', '', 1, 1, [0, 6], 0, ['\lim_{'],  ['}'])
call vit#NewTemplate('ViTSup',  'latex', '', 1, 1, [0, 6], 0, ['\sup_{'],  ['}'])
call vit#NewTemplate('ViTInf',  'latex', '', 1, 1, [0, 6], 0, ['\inf_{'],  ['}'])

unlet s:_

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ SCANNING ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

call vit#ScanFromLog(expand('%:p'), expand('%:p:h'))
call listener_add({bufnr, ... -> vit#ScanFromBuffer(expand('%:p'), expand('%:p:h'))}, s:buf)

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ CLEANUP ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

" reset cpoptions as per :h usr_41
let &cpo = s:save_cpo
unlet s:save_cpo

unlet s:buf

