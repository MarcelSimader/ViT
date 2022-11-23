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

if exists('g:vit_enable') && !g:vit_enable
    finish
endif

" set cpoptions as per :h usr_41
let s:save_cpo = &cpo
set cpo&vim

let s:bufname = bufname()

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ FILE TREE ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

call vit#ResetRootFile(s:bufname)

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ MODELINE ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

" parse compilation header once every time the ftplugin is loaded
call vit#ParseModeline(s:bufname)

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ OPTIONS ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

" set undo options
" TODO: does not work currently?
let b:undo_ftplugin +=
    \ '| setlocal conceallevel< completefunc< completeopt<'
    \.'| unlet b:indentLine_enabled'

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

if g:vit_enable_keybinds
    " Automatically insert second X and move in the middle X<Cursor>X
    for s:char in g:vit_autosurround_chars
        if len(s:char) == 2
            execute 'inoremap <buffer> '.s:char[0].' '.s:char[0].s:char[1].'<C-O>h'
        endif
    endfor
    unlet s:char

    " environment actions
    nnoremap <buffer> <C-E>d <Cmd>ViTEnvDelete<CR>
    nnoremap <buffer> <C-E>c <Cmd>ViTEnvChange<CR>

    " quick compiling
    nnoremap <buffer> " <Cmd>noautocmd update \| call vit#Compile(bufname())<CR>
    nnoremap <buffer> ! <Cmd>noautocmd update \| call vit#Compile(bufname(), "!")<CR>

    " cursor move
    execute 'inoremap <buffer> '.g:vit_leader.'<Tab> <Cmd>call vit#SmartMoveCursorRight()<CR>'
endif

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ COMMANDS ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

if g:vit_enable_commands
    command -buffer -bang -count=1 ViTCompile
                \ noautocmd update
                \ | call vit#Compile(bufname(), '<bang>', {'numcomps': <count>})

    " environment actions
    command -buffer ViTEnvDelete :call vit#DeleteCurrentTeXEnv()
    command -buffer ViTEnvChange :call vit#ChangeCurrentTeXEnv()

    command -buffer ViTStatus :call vit#Status(bufname())
endif

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ AUTOCOMMANDS ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

augroup ViT
    autocmd!

    " compile the modeline every time we save to update values
    autocmd BufWritePost <buffer> :call vit#ParseModeline(bufname())

    " compiling automatically
    autocmd BufWritePost <buffer>
                \ :if getbufvar(bufname(), 'vit_compile_on_write', g:vit_compile_on_write)
                \ | call vit#Compile(bufname(), '!')
                \ | endif

    " compile-sign hovering
    autocmd CursorMoved <buffer> :call vit#CompileSignHover()
augroup END

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ STATUSLINE ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

if !exists('*ViTStatusTeXEnv')
    function ViTStatusTeXEnv(airline = 0)
        let sep = a:airline ? g:airline_left_alt_sep.' ' : ''
        let env = trim(get(vitutil#CurrentTeXEnv(), 0, ''))
        return (len(env) < 1) ? sep.'' : sep.env
    endfunction
endif
if !exists('*ViTStatusline')
    function ViTStatusline(airline = 0)
        let sep = a:airline ? ' '.g:airline_right_alt_sep.' ' : ''
        let statusline = trim(vit#GetStatusline(bufname(), 1))
        return (len(statusline) < 1) ? '...'.sep : statusline.' '.sep
    endfunction
endif

if exists('*airline#add_statusline_func')
    " airline is installed
    if !exists('*ViTAirline')
        function ViTAirline(...)
            if &ft == 'latex'
                call airline#extensions#append_to_section(
                            \ 'c', '%{ViTStatusTeXEnv(1)}')
                call airline#extensions#prepend_to_section(
                            \ 'x', '%{ViTStatusline(1)}')
            endif
        endfunction
        call airline#add_statusline_func('ViTAirline')
    endif
else
endif
" regular statusline
setlocal statusline=%f\ \|\ %{ViTStatusline(0)}\ >\ %{ViTStatusTeXEnv(0)}

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ TEMPLATE DEFINITIONS ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

let s:_ = g:vit_leader

" ~~~~~~~~~~~~~~~~~~~~ general ~~~~~~~~~~~~~~~~~~~~

" ~~~~~~~~~~ text
call vit#NewTemplate('ViTEnv',          '<C-E>', 0, [1, 5], 4, ['\begin{#1}'],                                               ['\end{#1}'], 1, ['Name: '])
call vit#NewTemplate('ViTEnum',         s:_.'e', 0, [1, 5], 4, ['\begin{enumerate}'],                                        ['\end{enumerate}'])
call vit#NewTemplate('ViTEnumLeft',     s:_.'E', 0, [1, 5], 4, ['\begin{enumerate}[leftmargin=*,align=left]'],               ['\end{enumerate}'])
call vit#NewTemplate('ViTAlphEnum',     s:_.'l', 0, [1, 5], 4, ['\begin{enumerate}[label=\alph*)]'],                         ['\end{enumerate}'])
call vit#NewTemplate('ViTAlphEnumLeft', s:_.'L', 0, [1, 5], 4, ['\begin{enumerate}[label=\alph*),leftmargin=*,align=left]'], ['\end{enumerate}'])
call vit#NewTemplate('ViTItemize',      s:_.'i', 0, [1, 5], 4, ['\begin{itemize}'],                                          ['\end{itemize}'])
call vit#NewTemplate('ViTDescription',  s:_.'d', 0, [1, 5], 4, ['\begin{description}'],                                      ['\end{description}'])
call vit#NewTemplate('ViTCenter',       s:_.'c', 0, [1, 5], 4, ['\begin{center}'],                                           ['\end{center}'])
call vit#NewTemplate('ViTTabular',      s:_.'t', 0, [1, 5], 4, ['\begin{tabular}{#1}'],                                      ['\end{tabular}'], 1, ['Columns: '])

call vit#NewTemplate('ViTChapter',       s:_.'C',   0, [3], 0, ['\chapter{#1}',       '\label{chap:#/\s/-/1}'],  [''], 1, ['Name: '])
call vit#NewTemplate('ViTSection',       s:_.'s',   0, [3], 0, ['\section{#1}',       '\label{sec:#/\s/-/1}'],   [''], 1, ['Name: '])
call vit#NewTemplate('ViTSubSection',    s:_.'ss',  0, [3], 0, ['\subsection{#1}',    '\label{ssec:#/\s/-/1}'],  [''], 1, ['Name: '])
call vit#NewTemplate('ViTSubSubSection', s:_.'sss', 0, [3], 0, ['\subsubsection{#1}', '\label{sssec:#/\s/-/1}'], [''], 1, ['Name: '])
call vit#NewTemplate('ViTParagraph',     s:_.'p',   0, [3], 0, ['\paragraph{#1}',     '\label{par:#/\s/-/1}'],   [''], 1, ['Name: '])
call vit#NewTemplate('ViTSubParagraph',  s:_.'pp',  0, [3], 0, ['\subparagraph{#1}',  '\label{spar:#/\s/-/1}'],  [''], 1, ['Name: '])

" ~~~~~~~~~~ math
call vit#NewTemplate('ViTEquation', s:_.'q', 0, [1, 5], 4, ['\begin{equation*}'],    ['\end{equation*}'])
call vit#NewTemplate('ViTGather',   s:_.'g', 0, [1, 5], 4, ['\begin{gather*}'],      ['\end{gather*}'])
call vit#NewTemplate('ViTAlign',    s:_.'a', 0, [1, 5], 4, ['\begin{align*}'],       ['\end{align*}'])
call vit#NewTemplate('ViTAlignAt',  s:_.'A', 0, [1, 5], 4, ['\begin{alignat*}{#1}'], ['\end{alignat*}'], 1, ['Columns: '])
call vit#NewTemplate('ViTProof',    s:_.'r', 0, [1, 5], 4, ['\begin{proof}'],        ['\end{proof}'])
call vit#NewTemplate('ViTMatrix',   s:_.'m', 0, [1, 5], 4, ['\begin{matrix}{#1}'],   ['\end{matrix}'], 1, ['Columns: '])

" ~~~~~~~~~~~~~~~~~~~~ inline ~~~~~~~~~~~~~~~~~~~~

call vit#NewTemplate('ViTMathMode',    s:_.'$',    1, [0, 1],  0, ['$'],            ['$'])
call vit#NewTemplate('ViTParentheses', s:_.'1',    1, [0, 7],  0, ['\left( '],      [' \right)'])
call vit#NewTemplate('ViTBrackets',    s:_.'2',    1, [0, 7],  0, ['\left[ '],      [' \right]'])
call vit#NewTemplate('ViTBraces',      s:_.'3',    1, [0, 8],  0, ['\left\{ '],     [' \right\}'])
call vit#NewTemplate('ViTBars',        s:_.'4',    1, [0, 7],  0, ['\left| '],      [' \right|'])
call vit#NewTemplate('ViTOverbrace',   s:_.'<F1>', 1, [0, 11], 0, ['\overbrace{'],  ['}^{}'])
call vit#NewTemplate('ViTUnderbrace',  s:_.'<F2>', 1, [0, 12], 0, ['\underbrace{'], ['}_{}'])
call vit#NewTemplate('ViTBoxed',       s:_.'<F3>', 1, [0, 7],  0, ['\boxed{'],      ['}'])
call vit#NewTemplate('ViTFrac', '', 1, [0, 6], 0, ['\frac{'],  ['}{}'])
call vit#NewTemplate('ViTSqrt', '', 1, [0, 6], 0, ['\sqrt{'],  ['}'])
call vit#NewTemplate('ViTRoot', '', 1, [0, 6], 0, ['\sqrt['],  [']{}'])
call vit#NewTemplate('ViTSum',  '', 1, [0, 6], 0, ['\sum_{'],  ['}^{}'])
call vit#NewTemplate('ViTInt',  '', 1, [0, 6], 0, ['\int_{'],  ['}^{}'])
call vit#NewTemplate('ViTProd', '', 1, [0, 7], 0, ['\prod_{'], ['}^{}'])
call vit#NewTemplate('ViTLim',  '', 1, [0, 6], 0, ['\lim_{'],  ['}'])
call vit#NewTemplate('ViTSup',  '', 1, [0, 6], 0, ['\sup_{'],  ['}'])
call vit#NewTemplate('ViTInf',  '', 1, [0, 6], 0, ['\inf_{'],  ['}'])

unlet s:_

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ CLEANUP ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

" reset cpoptions as per :h usr_41
let &cpo = s:save_cpo
unlet s:save_cpo

unlet s:bufname

