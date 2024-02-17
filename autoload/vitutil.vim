" General utilities for the ViT Vim plugin.
" Author: Marcel Simader (marcel0simader@gmail.com)
" Date: 29.08.2022
" (c) Marcel Simader 2022

" Resets variable 'name' to copy of the global value 'g:name' in buffer 'buf' or to
" 'default' if global variable is not found.
function vitutil#ResetVar(buf, name, default = v:none)
    call setbufvar(bufname(a:buf), a:name,
                \ exists('g:'.a:name) ? copy(g:{a:name}) : a:default)
endfunction

" Retrieves the variable 'name' in buffer 'buf', or sets the value to 'default' if it is
" not found and no global value 'g:name' exists, otherwise set to copy of 'g:name'.
function vitutil#GetVar(buf, name, default = v:none)
    let buf = bufname(a:buf)
    " reset if not found already
    let bufvar = getbufvar(buf, a:name)
    if bufvar is v:none
        call vitutil#ResetVar(buf, a:name, a:default)
        return getbufvar(buf, a:name)
    else
        return bufvar
    endif
endfunction

" Prepare a list of argument strings for a process, replacing '%' with the filepath.
function vitutil#PrepareArgs(args, filepath)
    " replace % with the file in flags, \\\@<!% means match '%' only if it is not
    " preceeded by '\', so that we can escape % with \%
    return substitute(join(a:args, ' '), '\\\@<!%', a:filepath, 'g')
endfunction

" Same functionality as vitutil#PrepareFname() but applied to a whole list of names.
function vitutil#PrepareFnames(fnames, showerror = v:true, pwd = v:null)
    let out = []
    for fname in a:fnames
        let newfname = vitutil#PrepareFname(fname, a:showerror, a:pwd)
        if !empty(newfname) | let out += [newfname] | endif
    endfor
    return out
endfunction

" Make sure file name points to an actually existing file and make the path relative to
" the given pwd or the cwd if no value is given.
" Arguments:
"   fname, a filename to modify
"   [showerror,] if true, display an error message for an invalid file pointer, otherwise
"       just siltently ignore the file
"   [path,] the path to search in if the file is not found immediately, defaults to the
"       current working directory
function vitutil#PrepareFname(fname, showerror = v:true, path = v:null)
    let path = (a:path is v:null) ? getcwd() : a:path
    if filereadable(a:fname)
        " nothing needs to be done
        return a:fname
    endif
    " try to find file
    let tmpwd = fnamemodify(a:fname, ':h')
    let tmpfname = fnamemodify(a:fname, ':t')
    let found = findfile(tmpfname, tmpwd)
    if empty(found) || !filereadable(found)
        if a:showerror
            throw 'ViT: Unable to locate file "'.a:fname.'" relative to "'.tmpwd.'"'
        endif
    else
        return fnamemodify(found, ':p')
    endif
endfunction

" Returns a boolean value indicating whether a file exists or not. Similar to
" 'vitutil#PrepareFname'.
" Arguments:
"   fname, a filename to look for
"   [path,] the path to search in if the file is not found immediately, defaults to the
"       current working directory
function vitutil#FileExists(fname, path = v:null)
    let path = (a:path is v:null) ? getcwd() : a:path
    if filereadable(a:fname) | return 1 | endif
    " try to find file
    let tmpwd = fnamemodify(a:fname, ':h')
    let tmpfname = fnamemodify(a:fname, ':t')
    let found = findfile(tmpfname, tmpwd)
    return !empty(found) && filereadable(found)
endfunction

" Returns the word the cursor is hovering over along with its columns. 'Word' is broadly
" used to figure out where to start parsing for auto-completion suggestions. For instance
" 'This is a test {}\beg' should probably start off at '\'.
" Arguments:
"   [word_indicators,] a list of characters that preceed a word
" Returns:
"   the word under the cursor and the starting and ending columns as list
function vitutil#GetWordUnderCursor(
            \ word_indicators = [' ', '.', ',', ':', '!', '?', '=', '"',
            \                    '(', ')', '[', ']', '{', '}'],
            \ word_indicators_min1 = ['\'])
    let startcol = col('.') - 1
    let curline  = getline('.')
    let column   = startcol
    " now we go backwards in the line until we find something that
    " indicates a word is starting
    while column > 0
        let curchar = strcharpart(curline, column - 1, 1)
        if index(a:word_indicators_min1, curchar) != -1 | let column -= 1 | break | endif
        if index(a:word_indicators, curchar) != -1 | break | endif
        let column -= 1
    endwhile
    " and that is our position
    return [strcharpart(curline, column, startcol - column), column, startcol]
endfunction

" Escapes a string to make it a literal regex match.
" Arguments:
"   lit, the string to be matched literally
" Returns:
"   a regex to match the input literally
function vitutil#EscapeRegex(lit)
    return escape(a:lit, '.*][')
endfunction

" Returns the name and start position of the LaTeX environment the cursor is currently
" positioned in.
" Arguments:
"   [backwards,] whether to search forwards or backwards, defaults to backwards
"   [nameregex,] the regular expression that matches an environment name
" Returns:
"   a list of form [envname, lnum, col]
function vitutil#CurrentTeXEnv(backwards = 1, nameregex = '\_[^@\}#]\+')
    let n = a:nameregex
    let flags = (a:backwards ? 'b' : '').'cnWz'
    let [lnum, col] = searchpairpos('\\begin{'.n.'}', '', '\\end{'.n.'}', flags)
    " now we get '\begin{envname}'
    let matches = matchlist(getline(lnum), '\\\%(begin\|end\){\('.n.'\)}', col - 1)
    return [empty(matches) ? '' : get(matches, 1, ''), lnum, col]
endfunction

" Same as 'vitutil#CurrentTeXEnv' but returns the positions of both the begin and the end
" statements.
" Returns:
"   a list of form [envname, beginl-num, begin-col, e-lnum, e-col]
function vitutil#CurrentTeXEnvPositions(nameregex = '\_[^@\}#]\+')
    let [envname0, blnum, bcol] = vitutil#CurrentTeXEnv(1, a:nameregex)
    let [envname1, elnum, ecol] = vitutil#CurrentTeXEnv(0, vitutil#EscapeRegex(envname0))
    return [envname0, blnum, bcol, elnum, ecol + len(envname0) + len('\begin{}') + 1]
endfunction

