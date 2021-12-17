" Main ViT filetype plugin file.
" Author: Marcel Simader (marcel0simader@gmail.com)
" Date: 28.11.2021
" (c) Marcel Simader 2021

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ DEBUG ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

if !exists('*s:LoadTeXTended')
    function! s:LoadTeXTended()
        if &ft != 'latex'
            return
        endif
        " set 'did' vars to false
        unlet b:vit_did_filetype b:vit_did_syntax
                    \ b:vit_did_indent g:vit_did_filetypedetect
        " reload scripts
        let start = reltime()
        runtime autoload/vitlib.vim
        runtime indent/latex.vim
        runtime syntax/latex.vim
        runtime ftplugin/latex.vim
        runtime ftdetect/latex.vim
        runtime user/sexercise.vim
        echohl StatusLineTerm
        echomsg 'Loading ViT took '
                    \ .string(reltimefloat(reltime(start)) * 1000.0)
                    \ .'ms'
    endfunction
    command ViTLoadLocal :call <SID>LoadTeXTended()
endif

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ /DEBUG ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

" Start with LaTeX. This will also define b:did_ftplugin
runtime ftplugin/tex.vim

" acts as include guard
if exists("b:vit_did_filetype")
    finish
endif
let b:vit_did_filetype = 1

" set cpoptions as per :h usr_41
let s:save_cpo = &cpo
set cpo&vim

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ GLOBAL CONFIGS ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

" Adds a new ViT global config option. This only defines the
" vars once, and makes sure user wishes are granted. Merry Christmas.
" It also sets an optional default value if the assignment failed with
" the initially requested value.
function s:Config(name, value, default = v:none)
    try
        if !exists(a:name)
            let {a:name} = a:value
        endif
    catch
        if a:default != v:none
            let {a:name} = default
        endif
    endtry
endfunction

call s:Config('g:vit_leader', '<C-@>')
call s:Config('g:vit_compiler', 'pdflatex')
call s:Config('g:vit_compiler_flags', '')
call s:Config('g:vit_error_regexp', '! .*')
call s:Config('g:vit_error_line_regexp', '^l\.\d\+')
call s:Config('g:vit_jump_chars', [' ', '(', '[', '{'])
call s:Config('g:vit_comment_line', '% '.repeat('~', 70))
call s:Config('g:vit_commands', readfile(findfile('latex_commands.txt')), [])
call s:Config('g:vit_autosurround_chars', [
            \ ['(', ')'], ['[', ']'], ['{', '}'],
            \ ['$', '$']
            \ ])

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ OPTIONS ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

" set undo options
" TODO: does not work currently?
"let b:undo_ftplugin =
"    \ 'setlocal conceallevel< completefunc< completeopt<'
"    \.'| unlet b:tex_conceal b:indentLine_enabled b:tex_indent_items'

" ~~~~~~~~~~ definitely important for function of script
" set option to the above function
setlocal completefunc=ViTCompleteFunc

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

" map vim completion to <C-Space><C-Space> and <C-Space><Space>
inoremap <buffer> <C-@><C-@> <C-X><C-U>
inoremap <buffer> <C-@><Space> <C-X><C-U>
" map \ to open autocomplete and write \
imap <buffer> <BSlash> \<C-X><C-U>

" Moves cursor to the right to simulate the <Tab> behavior in other IDEs.
" Arguments:
"   lnum, the target line number
"   column, the minimum column for the cursor
"   chars, a list of characters to consider for a new column
function s:SmartMoveCursorRight(lnum, column, chars)
    " do actual smart movey things
    let line = getline(a:lnum)
    let cols = []
    for char in a:chars
        let cols += [stridx(line, char, a:column - 1) + 2]
    endfor
    call filter(cols, 'v:val > a:column')
    call cursor(a:lnum, len(cols) > 0 ? min(cols) : 999999)
endfunction
inoremap <buffer> <S-Tab> <C-O>:call <SID>SmartMoveCursorRight(line('.'), col('.'), g:vit_jump_chars)<CR>

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ COMMANDS ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

command -buffer -bang ViTCompile call <SID>ViTCompile(expand('%:p'), expand('%:p:h'), '<bang>')

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ AUTOCOMMANDS ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

" auto compiling
augroup ViTCompile
    autocmd!
    autocmd BufWritePost <buffer> :ViTCompile!
augroup END

" automatic completion-insert detection, triggering
" the command execution
augroup ViTCompletionDetection
    autocmd!
    autocmd CompleteDone <buffer> :call <SID>ViTCompletionDetection()
augroup END

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ COMPILING ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

" we only wanna define this sign once, probably
call sign_define('ViTError', #{text: '!>', texthl: 'ErrorMsg'})
function ViTCompileCallback(job, exit)
    if a:exit
        " get log file of current file, if possible
        try
            let logfile = readfile(expand('%:r').'.log')
            " create sign
            let errorline = str2nr(trim(matchstr(logfile, g:vit_error_line_regexp)[2:]))
            echomsg errorline
            let b:signid = sign_place(
                        \ 0, 'ViT', 'ViTError', bufname(), #{lnum: errorline})
            " output error message
            let errormsg = ': '.matchstr(logfile, g:vit_error_regexp)
        catch /.*E484.*/
            let errormsg = ', but no ".log" file found for this buffer.'
        endtry
        echohl ErrorMsg
        echomsg "Compiled with Errors".errormsg
    else
        " remove old sign
        if exists('b:signid')
            call sign_unplace('ViT', #{id: b:signid})
        endif
        echohl MoreMsg
        echo "Compiled Succesfully! Yay!"
    endif
    echohl None
endfunction

" Compiles the contents of a file using the configured LaTeX compiler.
" Arguments:
"   filepath, the path to the file
"   pwd, the path to the working directory (should be folder of
"       'filepath' resides in)
"   [silent,] can be '!' to be executed as background job, otherwise
"       open a new terminal window
"   [flags,] can be set to pass flags to the compiler
function s:ViTCompile(filepath, pwd, silent = '', flags = '')
    " save file
    w
    " run compilation
    if a:silent == '!'
        " run background job
        let s:se_latex_currjob = job_start(
            \ g:vit_compiler.' -halt-on-error '.g:vit_compiler_flags.' '.a:flags.' "'.a:filepath.'"',
            \ {'exit_cb': 'ViTCompileCallback', 'cwd': a:pwd}
            \ )
    else
        " open terminal
        :vertical :belowright call term_start(
            \ g:vit_compiler.' '.g:vit_compiler_flags.' '.a:flags.' "'.a:filepath.'"',
            \ {'term_finish': 'close', 'cwd': a:pwd}
            \ )
    endif
endfunction

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ TEMPLATING FUNCTIONS ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

" Replaces all appearances of '[#1, #2, ... #numargs]' in order, where
" 'inputnames' is the user prompt text in the same order. The rest
" parameter holds an arbitrary number of arrays containing lines that
" will have their '#1, #2, ...' replaced.
" Returns:
"   0 if the user aborted the completion, 1 otherwise
function s:ViTPromptTemplateCompletion(numargs, inputnames, ...)
    " replace template strings
    for i in range(1, a:numargs)
        let currIn = input(get(a:inputnames, i - 1, 'Argument '.i.': '))
        " if an input is empty, abort
        if empty(currIn)
            return 0
        endif
        " replace
        for arr in a:000
            for j in range(len(arr))
                let arr[j] = substitute(arr[j], '#'.i, currIn, 'g')
            endfor
        endfor
    endfor
    return 1
endfunction

" Sets up a new ViT template. These templates are used for the insert mode
" completion, and are also set up as command.
" Arguments:
"   name, the name of the command to be defined
"   keybind, the keybind to access this command, or '' for no keybind
"   inlinemode, '0' for no inline mode, '1' for inline mode
"   completionitem, whether to make this tempalte an auto-completion
"       entry upon creating the command (and possibly keybinds),
"       the call to 'ViTNewCompletionOption' will be made using
"       the first item of 'textbefore'
"   finalcursoroffset, the position that the cursor will be set to
"       upon completing the template
"   middleindent, the indent of text that the template surrounds in
"       surround mode
"   textbefore, an array of lines for the before-text
"   textafter, an array of lines for the after-text
"   numargs, the number of template parameters '#1, #2, ...' in the
"       'text(before|after)' arguments
"   ..., the rest parameter contains the names of the template
"        parameters, see 'ViTPromptTemplateCompletion'
function ViTNewTemplate(name, keybind, inlinemode, completionitem,
            \ finalcursoroffset, middleindent, textbefore, textafter, numargs, ...)
    " rename so we can use it in the closure
    let inputnames = a:000
    " ~~~~~~~~~~ command function
    function s:ViTNewCommandSub_{a:name}(lstart, lend, mode = 'i') closure
        let [textbefore, textafter] = [a:textbefore, a:textafter]
        let endcol = col('.')
        " templating
        if !s:ViTPromptTemplateCompletion(a:numargs, inputnames,
                    \ textbefore, textafter)
            return
        endif
        " setting cursor and line based on mode
        if a:mode == '' || (a:mode == 'i' && a:inlinemode == 1)
            " inline insert mode
            let [cstart, cend] = [col("."), col(".")]
        elseif a:mode == 'i' || a:mode == 'V'
            " line insert mode
            let [cstart, cend] = [0, 999999]
            let [textbefore, textafter] = [textbefore + [''], [''] + textafter]
        elseif a:mode == 'v'
            " character insert mode
            let [cstart, cend] = [col("'<"), col("'>") + 1]
            " possibly flip start and end cols
            if cstart > cend
                let [cstart, cend] = [cend, cstart]
            endif
        else
            echohl ErrorMsg
            echomsg 'Unknown mode '.a:mode.'.'
            echohl None
            return
        endif
        " calling insert
        call vitlib#SmartSurround(
                            \ a:lstart, a:lend, cstart, cend,
                            \ textbefore, textafter, a:middleindent,
                            \ )
        call cursor(a:lstart + get(a:finalcursoroffset, 0, 0),
                    \ endcol + get(a:finalcursoroffset, 1, 0))
    endfunction
    " ~~~~~~~~~~ command
    execute 'command -buffer -range -nargs=? '.a:name.' :call <SID>ViTNewCommandSub_'.a:name.'(<line1>, <line2>, "<args>")'
    " ~~~~~~~~~~ keymap
    if a:keybind != ''
        execute 'inoremap <buffer> '.a:keybind.' <C-O>:'.a:name.' i<CR>'
        execute 'xnoremap <buffer> <expr> '.a:keybind.' ":'.a:name.' ".mode()."<CR>"'
    endif
    " ~~~~~~~~~~ default completion option
    call ViTNewCompletionOption(a:textbefore[0], a:name)
endfunction

" Adds a template command to the insert mode completion menu.
" Arguments:
"   name, the name of the command in the completion menu
"   command, the name of the command to execute upon insertion
"   [mode,] defualts to 'i', the mode that is passed to the command
"       this must be a valid vim mode (i, V, v, ...)
function ViTNewCompletionOption(name, command, mode = 'i')
    " remove options with same name from list
    let idx = index(g:vit_commands, a:name)
    if idx != -1
        call remove(g:vit_commands, idx)
    endif
    " add new item to list
    let g:vit_commands += [{
                \ 'word': a:name,
                \ 'user_data': 'se_latex_'.a:command.'_'.a:mode
                \ }]
endfunction

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ COMPLETION ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

" Omnifunc, see :h complete-functions for more details
function ViTCompleteFunc(findstart, base)
    " get last 'word' under cursor
    if a:findstart
        let searchspace = strpart(getline('.'), 0, col('.') - 1)
        return max([0,
                  \ strridx(searchspace, ' ') + 1,
                  \ strridx(searchspace, '\')])
    endif
    " actually compute matches for 'a:base'
    " always include a:base in matches
    let matches = [a:base]
    for command in g:vit_commands
        " we could have a string or a dict here
        if type(command) == v:t_string
            let commandtext = command
        elseif type(command) == v:t_dict
            let commandtext = command['word']
        else
            echohl ErrorMsg
            echomsg 'Unknown type in ViTCompleteFunc: '.type(command)
            echohl None
            continue
        endif
        " add only if a:base is in commandtext
        if stridx(commandtext, a:base) != -1
            call add(matches, command)
        endif
    endfor
    return matches
endfunction

" Deletes the just inserted item and replaces it with a command encoded
" in the 'user_data' of the completion menu item if it came from this
" plugin.
function s:ViTCompletionDetection()
    let item = v:completed_item
    " stop if user_data does not exist on the item
    if empty(item) || !has_key(item, 'user_data')
        return
    endif
    " split into [WHOLE_MATCH, Command, mode, ...] or []
    let match = matchlist(item['user_data'], 'se_latex_\([A-Za-z0-9\-]*\)_\([ivV]\?\)')
    " return if we did not find at least [WHOLE_MATCH, Command]
    if empty(get(match, 0, '')) || empty(get(match, 1, ''))
        return
    endif
    " construct new line with removed 'word'
    let lnum = line('.')
    let line = getline(lnum)
    let col = col(lnum)
    let wordidx = strridx(line, item['word'])
    let wordlen = strlen(item['word'])
    let newline = strpart(line, 0, wordidx)
                \.strpart(line, wordidx + wordlen, 999999)
    " insert newline
    call setline(lnum, newline)
    call setpos('.', [bufnr(), lnum, wordidx + 1])
    " execute command given by item
    execute trim(join(match[1:], ' '))
endfunction

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ TEMPLATE DEFINITIONS ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

let s:_ = g:vit_leader

" ~~~~~~~~~~~~~~~~~~~~ general ~~~~~~~~~~~~~~~~~~~~

" ~~~~~~~~~~ text mode
call ViTNewTemplate('ViTProblem',   s:_.'p', 1, 0, [4], 0, [g:vit_comment_line, g:vit_comment_line, g:vit_comment_line, '\problem', ''],                    [], 0)
call ViTNewTemplate('ViTProblemnr', s:_.'P', 1, 0, [5], 0, [g:vit_comment_line, g:vit_comment_line, g:vit_comment_line, '\setproblem{#1}', '\problem', ''], [], 1, 'Number: ')

" ~~~~~~~~~~ text envs
call ViTNewTemplate('ViTEnv',          '<C-E>', 0, 1, [1, 5], 4, ['\begin{#1}'],                                               ['\end{#1}'],        1, 'Name: ')
call ViTNewTemplate('ViTEnum',         s:_.'e', 0, 1, [1, 5], 4, ['\begin{enumerate}'],                                        ['\end{enumerate}'], 0)
call ViTNewTemplate('ViTEnumLeft',     s:_.'E', 0, 1, [1, 5], 4, ['\begin{enumerate}[leftmargin=*,align=left]'],               ['\end{enumerate}'], 0)
call ViTNewTemplate('ViTAlphEnum',     s:_.'l', 0, 1, [1, 5], 4, ['\begin{enumerate}[label=\alph*)]'],                         ['\end{enumerate}'], 0)
call ViTNewTemplate('ViTAlphEnumLeft', s:_.'L', 0, 1, [1, 5], 4, ['\begin{enumerate}[label=\alph*),leftmargin=*,align=left]'], ['\end{enumerate}'], 0)
call ViTNewTemplate('ViTCenter',       s:_.'c', 0, 1, [1, 5], 4, ['\begin{center}'],                                           ['\end{center}'],    0)
call ViTNewTemplate('ViTTabular',      s:_.'t', 0, 1, [1, 5], 4, ['\begin{tabular}{#1}'],                                      ['\end{tabular}'],   1, 'Columns: ')

" ~~~~~~~~~~ math envs
call ViTNewTemplate('ViTEquation', s:_.'q', 0, 1, [1, 5], 4, ['\begin{equation*}'],    ['\end{equation*}'], 0)
call ViTNewTemplate('ViTGather',   s:_.'g', 0, 1, [1, 5], 4, ['\begin{gather*}'],      ['\end{gather*}'],   0)
call ViTNewTemplate('ViTAlign',    s:_.'a', 0, 1, [1, 5], 4, ['\begin{align*}'],       ['\end{align*}'],    0)
call ViTNewTemplate('ViTAlignAt',  s:_.'A', 0, 1, [1, 5], 4, ['\begin{alignat*}{#1}'], ['\end{alignat*}'],  1, 'Columns: ')
call ViTNewTemplate('ViTProof',    s:_.'r', 0, 1, [1, 5], 4, ['\begin{proof}'],        ['\end{proof}'],     0)
call ViTNewTemplate('ViTMatrix',   s:_.'m', 0, 1, [1, 5], 4, ['\begin{matrix}{#1}'],   ['\end{matrix}'],    1, 'Columns: ')

" ~~~~~~~~~~~~~~~~~~~~ inline ~~~~~~~~~~~~~~~~~~~~

call ViTNewTemplate('ViTMathMode',    s:_.'$',    1, 1, [0, 1],  0, ['$'],            ['$'],         0)
call ViTNewTemplate('ViTParentheses', s:_.'1',    1, 1, [0, 7],  0, ['\left( '],      [' \right)'],  0)
call ViTNewTemplate('ViTBrackets',    s:_.'2',    1, 1, [0, 7],  0, ['\left[ '],      [' \right]'],  0)
call ViTNewTemplate('ViTBraces',      s:_.'3',    1, 1, [0, 8],  0, ['\left\{ '],     [' \right\}'], 0)
call ViTNewTemplate('ViTBars',        s:_.'4',    1, 1, [0, 7],  0, ['\left| '],      [' \right|'],  0)
call ViTNewTemplate('ViTOverbrace',   s:_.'<F1>', 1, 1, [0, 11], 0, ['\overbrace{'],  ['}^{}'],      0)
call ViTNewTemplate('ViTUnderbrace',  s:_.'<F2>', 1, 1, [0, 12], 0, ['\underbrace{'], ['}_{}'],      0)
call ViTNewTemplate('ViTBoxed',       s:_.'<F3>', 1, 1, [0, 7],  0, ['\boxed{'],      ['}'],         0)

" ~~~~~~~~~~~~~~~~~~~~ menu options ~~~~~~~~~~~~~~~~~~~~

call ViTNewTemplate('ViTFrac', '', 1, [0, 6],  0, 1, ['\frac{'],  ['}{}'],  0)
call ViTNewTemplate('ViTSum',  '', 1, [0, 6],  0, 1, ['\sum_{'],  ['}^{}'], 0)
call ViTNewTemplate('ViTInt',  '', 1, [0, 6],  0, 1, ['\int_{'],  ['}^{}'], 0)
call ViTNewTemplate('ViTProd', '', 1, [0, 7],  0, 1, ['\prod_{'], ['}^{}'], 0)
call ViTNewTemplate('ViTLim',  '', 1, [0, 6],  0, 1, ['\lim_{'],  ['}'],    0)
call ViTNewTemplate('ViTSup',  '', 1, [0, 6],  0, 1, ['\sup_{'],  ['}'],    0)
call ViTNewTemplate('ViTInf',  '', 1, [0, 6],  0, 1, ['\inf_{'],  ['}'],    0)

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ CLEANUP ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

unlet s:_

" reset cpoptions as per :h usr_41
let &cpo = s:save_cpo
unlet s:save_cpo

