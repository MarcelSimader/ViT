" Functions for the ViT plugin that are only loaded once.
" Author: Marcel Simader (marcel0simader@gmail.com)
" Date: 26.12.2021
" (c) Marcel Simader 2021

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ DEBUG ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

if !exists('*s:LoadViT')
    function! s:LoadViT()
        if &ft != 'latex'
            return
        endif
        let buf = bufname()
        unlet g:vit_did_plugin g:vit_did_ftdetect
        call setbufvar(buf, 'current_syntax', '')
        call setbufvar(buf, 'did_ftplugin', '')
        " reload scripts
        let start = reltime()
        for file in ['ftdetect/latex.vim', 'ftplugin/latex.vim', 'plugin/vit.vim',
                    \ 'syntax/latex.vim', 'user/*.vim']
            execute 'runtime '.file
        endfor
        echohl StatusLineTerm
        echomsg 'Loading ViT took '
                    \ .string(reltimefloat(reltime(start)) * 1000.0)
                    \ .'ms'
        echohl None
    endfunction
    command ViTLoadLocal :call <SID>LoadViT()
endif

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ /DEBUG ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

" acts as include guard
if exists('g:vit_did_plugin')
    finish
endif
let g:vit_did_plugin = 1

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ GLOBAL CONFIGS ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

" Adds a new ViT global config option. This only defines the
" vars once, and makes sure user wishes are granted. Merry Christmas.
" It also sets an optional default value if the assignment failed with
" the initially requested value.
function s:Config(name, value, default = v:none)
    try
        if !exists(a:name) | let {a:name} = a:value() | endif
    catch
        echohl WarningMsg
        echomsg 'ViT Warning: Problem while processing "'.a:name.'" ('.v:exception.')'
        echohl None
        let {a:name} = a:default
    endtry
endfunction

call s:Config('g:vit_leader', {-> '<C-@>'})
call s:Config('g:vit_compiler', {-> 'pdflatex'})
call s:Config('g:vit_compiler_flags', {-> ''})
call s:Config('g:vit_max_errors', {-> 10})
call s:Config('g:vit_error_regexp', {-> '^!\s*\(.*\).*$'})
call s:Config('g:vit_error_line_regexp', {-> '^l\.\(\d\+\).*$'})
" TODO: document this
call s:Config('g:vit_identifier_regexp', {-> '[_\-\*\\A-Za-z0-9]'})
call s:Config('g:vit_jump_chars', {-> [' ', '(', '[', '{']})
call s:Config('g:vit_template_remove_on_abort', {-> 1})
call s:Config('g:vit_comment_line', {-> '% '.repeat('~', 70)})
call s:Config('g:vit_commands',
            \ {-> readfile(findfile('latex_commands.txt', &runtimepath))}, [])
call s:Config('g:vit_autosurround_chars', {-> [
            \ ['(', ')'], ['[', ']'], ['{', '}'], ['$', '$']
            \ ]})

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ COMPILING ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

" Compiles the contents of a file using the configured LaTeX compiler.
" Arguments:
"   filepath, the path to the file
"   pwd, the path to the working directory (should be folder of
"       'filepath' resides in)
"   [silent,] can be '!' to be executed as background job, otherwise
"       open a new terminal window
"   [flags,] can be set to pass flags to the compiler
function vit#Compile(filepath, pwd, silent = '', flags = '')
    " save file
    w
    " run compilation
    if a:silent == '!'
        " run background job
        let s:se_latex_currjob = job_start(
            \ g:vit_compiler.' --interaction=nonstopmode'
            \     .g:vit_compiler_flags.' '.a:flags.' "'.a:filepath.'"',
            \ {'exit_cb': 'vit#CompileCallback', 'cwd': a:pwd})
    else
        " open terminal
        :vertical :belowright call term_start(
            \ g:vit_compiler.' '.g:vit_compiler_flags.' '
            \     .a:flags.' "'.a:filepath.'"',
            \ {'term_finish': 'close', 'cwd': a:pwd})
    endif
endfunction

if g:vit_max_errors > 0
    call sign_define('ViTError', #{text: '!>', texthl: 'ViTErrorSign'})
endif
function vit#CompileCallback(job, exit)
    let buf = bufname()
    " remove old signs
    if g:vit_max_errors > 0
        call setbufvar(buf, 'vit_signs', {})
        call sign_unplace('ViT')
    endif
    " success
    if a:exit == 0
        echohl MoreMsg | echo 'Compiled succesfully! Yay!' | echohl None
        return
    endif
    " get log file of current file, if possible
    try
        let statusmsgs = []
        " read signs dict
        let vit_signs_dict = getbufvar(buf, 'vit_signs', {})
        " loop over lines in logfile
        let [logfile, lnum, num_matched] = [readfile(expand('%:r').'.log'), 0, 0]
        let logfile_len = len(logfile)
        while lnum < logfile_len && num_matched < g:vit_max_errors
            " try to match message for error
            let m_err = matchlist(logfile[lnum], g:vit_error_regexp)
            if len(m_err) >= 2
                let errmsg = trim(m_err[1])
                " try to match line for error, we go for as long as we can here
                let added_statusmsg = 0
                while (lnum + 1) < logfile_len
                    let lnum += 1
                    let l_err = matchlist(logfile[lnum], g:vit_error_line_regexp)
                    if len(l_err) >= 2
                        let errline = str2nr(trim(l_err[1]))
                        " set all things related to the errors
                        call sign_place(0, 'ViT', 'ViTError', buf, #{lnum: errline})
                        let vit_signs_dict[errline] = errmsg
                        let num_matched += 1
                        let statusmsgs += ['Compiled with errors (line '
                                    \      .errline.'): '.errmsg]
                        let added_statusmsg = 1
                        " and we can stop now
                        break
                    endif
                endwhile
                if !added_statusmsg
                    let statusmsgs += ['Compiled with errors: '.errmsg]
                endif
            endif
            let lnum += 1
        endwhile
        call setbufvar(buf, 'vit_signs', vit_signs_dict)

        echohl ErrorMsg
        if !empty(statusmsgs)
            echomsg statusmsgs[0]
        else
            if g:vit_max_errors == 0
                echomsg 'Compiled wtih errors.'
            else
                echomsg 'Compiled with errors, but no error messages found in .log file.'
            endif
        endif
        echohl None
    catch /.*E484.*/
        echohl ErrorMsg
        echomsg 'Compiled with errors, but found no .log file for this buffer.'
        echohl None
    endtry
endfunction

function vit#CompileSignHover()
    let vit_sign_msg = get(getbufvar(bufname(), 'vit_signs', {}), line('.'), '')
    if !empty(vit_sign_msg)
        echohl ErrorMsg | redraw | echo vit_sign_msg | echohl None
    endif
endfunction

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ HIGHLIGHTING GROUPS ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

highlight ViTErrorSign ctermfg=Red ctermbg=DarkRed

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ TEMPLATING FUNCTIONS ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

" Legacy API.
function ViTNewTemplate(name, keybind, inlinemode, completionitem,
            \ finalcursoroffset, middleindent, textbefore, textafter,
            \ numargs = 0, argname = [], argdefault = [], argcomplete = [])
    return vit#NewTemplate(a:name, a:keybind, a:inlinemode, a:completionitem,
                \ a:finalcursoroffset, a:middleindent, a:textbefore, a:textafter,
                \ a:numargs, a:argname, a:argdefault, a:argcomplete)
endfunction

" Sets up a new ViT template.
" Arguments:
"   name, the name of the command to be defined
"   keybind, the keybind to access this command, or '' for no keybind
"   inlinemode, '0' for no inline mode, '1' for inline mode
"   completionitem, whether to make this tempalte an auto-completion
"       entry upon creating the command (and possibly keybinds),
"       the call to 'vit#NewCompletionOption' will be made using
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
function vit#NewTemplate(name, keybind, inlinemode, completionitem,
            \ finalcursoroffset, middleindent, textbefore, textafter,
            \ numargs = 0, argname = [], argdefault = [], argcomplete = [])
    let id = rand(srand())
    " ~~~~~~~~~~ command function
    function! s:ViTNewCommandSub_{id}_{a:name}(lstart, lend, mode = 'i') closure
        let endcol = col('.')
        let [textbefore, textafter] = [a:textbefore, a:textafter]
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
            if cstart > cend | let [cstart, cend] = [cend, cstart] | endif
        else
            throw 'Unknown mode "'.a:mode.'".'
        endif
        " save undo state
        let undostate = undotree()['seq_cur']
        " insert
        call vimse#SmartSurround(
                            \ a:lstart, a:lend, cstart, cend,
                            \ textbefore, textafter, a:middleindent)
        " handle templating
        let result = vimse#TemplateString(a:lstart,
                    \ a:lend + len(textbefore) + len(textafter),
                    \ 0, 999999, a:numargs, a:argname, a:argdefault, a:argcomplete)
        " undo and return if result was false
        if !result && g:vit_template_remove_on_abort
            " set to 'undostate' for all other changes
            " and undo once for this method
            silent execute 'undo '.undostate | silent undo | return
        endif
        " else set cursor pos in new text
        call cursor(a:lstart + get(a:finalcursoroffset, 0, 0),
                    \ endcol + get(a:finalcursoroffset, 1, 0))
    endfunction
    " ~~~~~~~~~~ command
    execute 'command! -buffer -range -nargs=? '.a:name
                \ .' :call <SID>ViTNewCommandSub_'.id.'_'.a:name.'(<line1>, <line2>, "<args>")'
    " ~~~~~~~~~~ keymap
    if a:keybind != ''
        execute 'inoremap <buffer> '.a:keybind.' <C-O>:'.a:name.' i<CR>'
        execute 'xnoremap <buffer> <expr> '.a:keybind.' ":'.a:name.' ".mode()."<CR>"'
    endif
    " ~~~~~~~~~~ default completion option
    if a:completionitem && len(a:textbefore) > 0
        call vit#NewCompletionOption(a:textbefore[0], a:name.' i')
    endif
endfunction

" Legacy API.
function ViTNewCompletionOption(name, command, ...)
    return vit#NewCompletionOption(a:name, a:command)
endfunction

" Adds a template command to the insert mode completion menu.
" Arguments:
"   name, the name of the command in the completion menu
"   command, the name of the command to execute upon insertion
function vit#NewCompletionOption(name, command, ...)
    let buf = bufname()
    " remove options with same name from list
    let vit_commands = getbufvar(buf, 'vit_commands', copy(g:vit_commands))
    let idx = index(vit_commands, a:name)
    if idx != -1 | call remove(vit_commands, idx) | endif
    " add new item to list
    if empty(a:command)
        let vit_commands += [a:name]
    else
        let vit_commands += [{'word': a:name, 'user_data': 'se_latex_'.a:command}]
    endif
    call setbufvar(buf, 'vit_commands', vit_commands)
endfunction

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ COMPLETION ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

" Omnifunc, see :h complete-functions for more details
function vit#CompleteFunc(findstart, base)
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
    for command in getbufvar(bufname(), 'vit_commands', g:vit_commands)
        " we could have a string or a dict here
        if type(command) == v:t_string
            let commandtext = command
        elseif type(command) == v:t_dict
            let commandtext = command['word']
        else
            throw 'Unknown completion item type "'.type(command).'".'
        endif
        " add only if a:base is in commandtext
        if stridx(commandtext, a:base) != -1
            let matches += [command]
        endif
    endfor
    return matches
endfunction

" Deletes the just inserted item and replaces it with a command encoded
" in the 'user_data' of the completion menu item if it came from this
" plugin.
function vit#CompletionDetection()
    let item = v:completed_item
    " stop if user_data does not exist on the item
    if empty(item) || !has_key(item, 'user_data')
        return
    endif
    " split into [WHOLE_MATCH, Command, mode, ...] or []
    let match = matchlist(item['user_data'], 'se_latex_\([\-\*\\A-Za-z0-9 \t]*\)')
    " return if we did not find at least [WHOLE_MATCH, Command]
    if empty(get(match, 0, '')) || empty(get(match, 1, ''))
        return
    endif
    " construct new line with removed 'word'
    let [lnum, col, line] = [line('.'), col('.'), getline('.')]
    let wordlen = strlen(item['word'])
    let newline = strpart(line, 0, col - wordlen - 1).strpart(line, col - 1, 999999)
    call setline(lnum, newline)
    " put cursor back
    call setpos('.', [bufnr(), lnum, col - wordlen])
    " execute command given by item
    execute match[1]
endfunction

" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~ UTILITY FUNCTIONS ~~~~~~~~~~~~~~~~~~~~
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

" Moves cursor to the right to simulate the <Tab> behavior in other IDEs.
" Arguments:
"   [chars,] defaults to 'g:vit_jump_chars', a list of characters to
"       consider for a new column
function vit#SmartMoveCursorRight(chars = g:vit_jump_chars)
    let [lnum, col, line] = [line('.'), col('.'), getline('.')]
    " do actual smart movey things
    let cols = []
    for char in a:chars
        let newidx = stridx(line, char, col - 1) + 2
        " only add after cursor
        if newidx > col
            let cols += [newidx]
        endif
        " break loop if we found a min already
        if newidx == col + 1
            break
        endif
    endfor
    call cursor(lnum, len(cols) > 0 ? min(cols) : 999999)
endfunction

function vit#CurrentTeXEnv()
    let flags = 'bcnWz'
    " search for \begin{...} \end{...}
    let [lnum, col] = searchpairpos('\\begin{'.g:vit_identifier_regexp.'\+}', '',
                                  \   '\\end{'.g:vit_identifier_regexp.'\+}', flags)
    " now we get 'envname}...'
    let envname = getline(lnum)[col + 6:]
    " now we get 'envname'
    let envname = envname[:stridx(envname, '}') - 1]
    return envname
endfunction

function vit#ScanNewCommands()
    for lnum in range(0, line('$'))
        let line = getline(lnum)
        if empty(line) | continue | endif
        let match = matchlist(line,
                    \ '\\newcommand{\('.g:vit_identifier_regexp.'\+\)}'
                    \.'\(\[\([0-9]\+\)\]\)\?')
        if len(match) >= 2
            let [name, numargs] = [match[1], str2nr(get(match, 3, '0'))]
            if numargs >= 1 | let name .= '{' | endif
            call vit#NewCompletionOption(name, '')
        endif
    endfor
endfunction

