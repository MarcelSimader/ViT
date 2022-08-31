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

