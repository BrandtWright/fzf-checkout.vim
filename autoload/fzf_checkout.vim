" See valid atoms in
" https://github.com/git/git/blob/076cbdcd739aeb33c1be87b73aebae5e43d7bcc5/ref-filter.c#L474
let s:format = shellescape(
      \ '%(color:#cfc68c)%(refname:short)  ' .
      \ '%(color:reset)%(color:#8dcf8c)%(subject) ' .
      \ '%(color:reset)%(color:#cf8ca7)%(committerdate:relative) ' .
      \ '%(color:reset)%(color:#8c9dcf)-> %(objectname:short)'
      \)
let s:color_regex = '\e\[[0-9;]\+m'


let s:branch_keybindings = {}
for [s:action, s:value] in items(g:fzf_branch_actions)
  let s:keymap = s:value['keymap']
  if !empty(s:keymap)
    let s:branch_keybindings[s:keymap] = s:action
  endif
endfor

let s:tag_keybindings = {}
for [s:action, s:value] in items(g:fzf_tag_actions)
  let s:keymap = s:value['keymap']
  if !empty(s:keymap)
    let s:tag_keybindings[s:keymap] = s:action
  endif
endfor

let s:actions = {'tag': g:fzf_tag_actions, 'branch': g:fzf_branch_actions}
let s:keybindings = {'tag': s:tag_keybindings, 'branch': s:branch_keybindings}
let s:branch_filters = {
      \ '--all': '--all',
      \ '--locals': '',
      \ '--remotes': '--remotes',
      \}


function! fzf_checkout#execute(type, action, lines) abort
  if len(a:lines) < 2
    return
  endif

  let l:trimchars = " \r\t\n\"'"
  let l:input = trim(shellescape(a:lines[0]), l:trimchars)
  let l:key = a:lines[1]
  let l:actions = s:actions[a:type]
  let l:action = a:action

  if empty(l:action)
    let l:action = get(s:keybindings[a:type], l:key)
    if string(l:action) ==# '0'
      return
    endif
  elseif l:key !=# 'enter'
    return
  endif

  let l:branch = ''
  if len(a:lines) > 2
    if l:actions[l:action]['multiple']
      let l:branch = join(
            \ map(a:lines[2:], 'trim(shellescape(split(v:val)[0]), l:trimchars)'),
            \ ' '
            \)
      let l:branch = trim(l:branch)
    else
      let l:branch = trim(shellescape(split(a:lines[2])[0]), l:trimchars)
    endif
  endif

  let l:required = l:actions[l:action]['required']

  let l:branch_required = index(l:required, 'branch') >= 0 || index(l:required, 'tag') >= 0
  if l:branch_required && empty(l:branch)
    call s:warning('A ' . a:type . ' is required')
    return
  endif

  let l:input_required = index(l:required, 'input') >= 0
  if l:input_required && empty(l:input)
    call s:warning('An input is required')
    return
  endif

  if l:actions[l:action]['confirm']
    let l:choice = confirm(
          \'Do you want to ' . l:action . ' ' . l:branch . '?',
          \ "&Yes\n&No", 2
          \)
    if l:choice != 1
      return
    endif
  endif

  let l:Execute_command = l:actions[l:action]['execute']
  if type(l:Execute_command) == v:t_string
    let l:Execute_command = substitute(l:Execute_command, '{git}', g:fzf_checkout_git_bin, 'g')
    let l:Execute_command = substitute(l:Execute_command, '{cwd}', fzf_checkout#get_cwd(), 'g')
    let l:Execute_command = substitute(l:Execute_command, '{branch}', l:branch, 'g')
    let l:Execute_command = substitute(l:Execute_command, '{tag}', l:branch, 'g')
    let l:Execute_command = substitute(l:Execute_command, '{input}', l:input, 'g')
    execute l:Execute_command
  elseif type(l:Execute_command) == v:t_func
    call l:Execute_command(g:fzf_checkout_git_bin, l:branch, l:input)
  endif

endfunction


function! s:warning(msg) abort
    echohl WarningMsg | echomsg a:msg | echohl None
endfunction


function! fzf_checkout#get_current_ref() abort
  " Try to get the branch name or fallback to get the commit.
  let l:git_cwd = fzf_checkout#get_cwd()
  let l:git_cmd = printf('%s -C %s symbolic-ref --short -q HEAD || %s -C %s rev-parse --short HEAD',
        \ g:fzf_checkout_git_bin,
        \ l:git_cwd,
        \ g:fzf_checkout_git_bin,
        \ l:git_cwd
        \)
  let l:current = system(l:git_cmd)
  let l:current = substitute(l:current, '\n', '', 'g')
  return l:current
endfunction


function! fzf_checkout#get_previous_ref() abort
  " Try to get the branch name or fallback to get the commit.
  let l:git_cwd = fzf_checkout#get_cwd()
  let l:git_cmd = printf('%s -C %s rev-parse -q --abbrev-ref --symbolic-full-name "@{-1}"',
        \ g:fzf_checkout_git_bin,
        \ l:git_cwd,
        \)
  let l:previous = system(l:git_cmd)
  if v:shell_error != 0 || l:previous =~# '^\s*$'
    let l:git_cmd = printf('%s -C %s rev-parse --short -q "@{-1}"',
        \ g:fzf_checkout_git_bin,
        \ l:git_cwd,
        \)
    let l:previous = system(l:git_cmd)
  endif
  let l:previous = substitute(l:previous, '\n', '', 'g')
  return l:previous
endfunction


function! s:remove_branch(branches, pattern) abort
  " Find first occurrence and remove it
  let l:index = match(a:branches, '^' . s:color_regex . a:pattern)
  if (l:index != -1)
    call remove(a:branches, l:index)
    return v:true
  endif
  return v:false
endfunction


function! fzf_checkout#list(bang, type, options, deprecated) abort
  let l:actions = s:actions[a:type]
  let l:options = split(a:options)
  let l:action = ''
  let l:filter = '--all'

  if len(l:options) > 2
    call s:warning('Maximum two arguments are allowed')
    return
  endif

  if !empty(l:options)
    if has_key(l:actions, l:options[0])
      let l:action = l:options[0]
    elseif a:type ==# 'branch' && has_key(s:branch_filters, l:options[0])
      let l:filter = l:options[0]
    endif
  endif

  if len(l:options) > 1
    if has_key(l:actions, l:options[1])
      let l:action = l:options[1]
    elseif a:type ==# 'branch' && has_key(s:branch_filters, l:options[1])
      let l:filter = l:options[1]
    endif
  endif

  if a:type ==# 'branch'
    let l:name = 'GBranches'
    let l:prompt = 'Branches> '
    let l:subcommand = 'branch ' . s:branch_filters[l:filter]

    if a:deprecated
      call s:warning('The :GCheckout command is deprecated, use :GBranches instead')
    endif
  elseif a:type ==# 'tag'
    let l:name = 'GTags'
    let l:prompt = 'Tags> '
    let l:subcommand = 'tag'

    if a:deprecated
      call s:warning('The :GCheckoutTag command is deprecated, use :GTags instead')
    endif
  else
    return
  endif

  " Allow all keybindings if isn't a specific task.
  if empty(l:action)
    let l:keybindings = keys(get(s:keybindings, a:type))
  else
    let l:keybindings = ['enter']
  endif

  if !empty(l:action)
    let l:prompt = l:actions[l:action]['prompt']
  endif

  let l:git_cmd = printf('%s -C %s %s --color=always --sort=refname:short --format=%s %s',
        \ g:fzf_checkout_git_bin,
        \ fzf_checkout#get_cwd(),
        \ l:subcommand,
        \ s:format,
        \ g:fzf_checkout_git_options
        \)

  let l:git_output = system(l:git_cmd)

  if v:shell_error != 0
    echo l:git_output
    return
  endif

  let l:git_output = split(l:git_output, '\n')

  " Delete the current and HEAD from the list.
  let l:current = fzf_checkout#get_current_ref()
  call s:remove_branch(l:git_output, escape(l:current, '/'))
  call s:remove_branch(l:git_output, '\(origin/\)\?HEAD')

  if g:fzf_checkout_previous_ref_first
    " Put previous ref first
    let l:previous = fzf_checkout#get_previous_ref()
    if !empty(l:previous)
      if (s:remove_branch(l:git_output, escape(l:previous, '/')))
        call insert(l:git_output, system(l:git_cmd . ' --list ' . l:previous), 0)
      endif
    endif
  endif

  let l:valid_keys = join(l:keybindings, ',')
  let l:fzf_options = [
        \ '--prompt', l:prompt,
        \ '--header', l:current,
        \ '--nth', '1',
        \ '--multi',
        \ '--expect', l:valid_keys,
        \ '--ansi',
        \ '--print-query',
        \ '--no-sort',
        \]
  call fzf#run(fzf#wrap(
        \ l:name,
        \ {
        \   'source': l:git_output,
        \   'sink*': function('fzf_checkout#execute', [a:type, l:action]),
        \   'options': l:fzf_options,
        \ },
        \ a:bang,
        \))
endfunction


function! fzf_checkout#complete_tags(arglead, cmdline, cursorpos) abort
  let l:cmdlist = split(a:cmdline)
  if len(l:cmdlist) > 2 || len(l:cmdlist) > 1 && empty(a:arglead)
    return ''
  endif

  let l:options = keys(g:fzf_tag_actions)
  return join(l:options, "\n")
endfunction


function! fzf_checkout#complete_branches(arglead, cmdline, cursorpos) abort
  let l:cmdlist = split(a:cmdline)
  if len(l:cmdlist) > 3 || len(l:cmdlist) > 2 && empty(a:arglead)
    return ''
  endif

  let l:options =  keys(g:fzf_branch_actions) + keys(s:branch_filters)
  if len(l:cmdlist) == 2
    if index(keys(g:fzf_branch_actions), l:cmdlist[1]) >= 0
      let l:options =  keys(s:branch_filters)
    elseif index(keys(s:branch_filters), l:cmdlist[1]) >= 0
      let l:options =  keys(g:fzf_branch_actions)
    endif
  endif

  return join(l:options, "\n")
endfunction

function! fzf_checkout#get_cwd() abort
  if g:fzf_checkout_use_current_buf_cwd
    let l:cwd = expand('%:p:h')

    " If we are in a fugitive buffer, remove the .git directory.
    if &filetype ==# 'fugitive'
      let l:cwd = substitute(l:cwd, '\(.\+\)\.git$', '\1', 'g')
    endif

    " Extract the cwd from a terminal buffer.
    " :h terminal-start
    if &buftype ==# 'terminal'
      let l:match = matchlist(l:cwd, '^term://\(.\+\)//')
      if !empty(l:match)
        let l:cwd = fnamemodify(l:match[1], ':p:h')
      endif
    endif
  else
    let l:cwd = getcwd()
  endif
  return shellescape(l:cwd)
endfunction
