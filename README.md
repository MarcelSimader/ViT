# ViT

ViT is a witty plugin for Vim LaTeX support!  This project is in an incredibly early
stage, don't rely on it in any way and don't expect anything of it. Changes are made to my
whim, or vim...  I'll see myself out. But really, this project is basically an efficiency
tool for myself, so if you want to use it that is on you.

## Features

Some of the main features are:

- Compilation commands and automatic compilation.
- Log file parsing for errors, error signs, and quick-fix list entries.
- Templating system to easily insert complex structures, with input variables and a
  lot of predefined templates.
- Automatically closed delimiters and (slightly) better cursor navigation for
  LaTeX files.
- Some smaller things...

## How to Install

Using ``vim-plug`` the process is quite easy, just add this to your ``.vimrc``:
```vimscript
call plug#begin('path-to-plugin-directory')
Plug 'MarcelSimader/VimSE' #{ tag: 'v1.*' }
    Plug 'MarcelSimader/ViT'
call plug#end()
```
ViT depends on the VimSE 'runtime library', so that plugin will need to be installed as
well.

### Recommended Installation

My recommended installation includes an LSP server which provides language data,
auto-completion suggestions, and all sorts of other things -- far better than this plugin
could ever muster on its own. All one needs to do to use it is to include the following
plugins,
```vimscript
Plug 'MarcelSimader/VimSE' #{ tag: 'v1.*' }
    Plug 'MarcelSimader/ViT'
" Base support for LSP servers in Vim.
Plug 'prabirshrestha/vim-lsp'
    " Provides the ':LspInstallServer' command.
    Plug 'mattn/vim-lsp-settings'
    " Optional, for auto-completion support.
    Plug 'prabirshrestha/asyncomplete.vim'
    Plug 'prabirshrestha/asyncomplete-lsp.vim'
```
and then run the command `:LspInstallServer texlab` (or another LSP server of your
choice). For odd reasons it is important that you run this command from within a TeX or
LaTeX buffer. Don't ask me...

## How to Contribute

I have no idea to be honest, but you are welcome to. Just try to follow sensible style for
the VimScript, open a feature branch, and submit a Pull Request.

## Other Notes

This plugin is intended mainly for typesetting mathematics in LaTeX. It is meant as
general LaTeX filetype plugin, and it probably does not work well for ``.cls`` or ``.sty``
files.

ViT is distributed under the Vim license. See the LICENSE file or ``:h license`` inside
Vim.

