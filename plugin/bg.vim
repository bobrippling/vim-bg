" [{ desc, handle, cmd, loclist_winid }, ...]
"                       ^~~~~~~~~~~~~ or 0
let s:jobs = []

function! s:bg_append(loclist_winid, line)
	let line = a:line
	let line = substitute(line, '\r$', '', 'g')

	if a:loclist_winid
		let flags = "a" " add to list
		call setloclist(a:loclist_winid, [], flags, {
		\   'lines': [line],
		\ })
	else
		caddexpr line
	endif
endfunction

function! s:bg_exit_cb(loclist_winid, job, exitcode)
	let i = 0
	for job in s:jobs
		if job.handle == a:job
			call s:bg_append(a:loclist_winid, '--- ' . job.desc . ' exited with ' . a:exitcode . ' ---')
			call remove(s:jobs, i)
			break
		endif
		let i = i + 1
	endfor
endfunction

function! s:bg_out_cb(loclist_winid, ch, line)
	" standard out
	call s:bg_append(a:loclist_winid, a:line)
endfunction

function! s:bg_err_cb(loclist_winid, ch, line)
	" standard error
	call s:bg_append(a:loclist_winid, a:line)
endfunction

function! s:bg_outerr_cb_nvim(loclist_winid, jobid, data, event, self)
	" let eof = (a:data == [''])

	let a:self.incomplete_line .= a:data[0]

	" we've completed the last line
	if !empty(a:self.incomplete_line)
		call s:bg_out_cb(a:loclist_winid, a:jobid, a:self.incomplete_line)
	endif

	for ent in a:data[1:-2]
		call s:bg_out_cb(a:loclist_winid, a:jobid, ent)
	endfor

	let a:self.incomplete_line = a:data[-1]
endfunction

function! s:bg_out_cb_nvim(loclist_winid, jobid, data, event) dict
	call s:bg_outerr_cb_nvim(a:loclist_winid, a:jobid, a:data, a:event, self)
endfunction

function! s:bg_err_cb_nvim(loclist_winid, jobid, data, event) dict
	call s:bg_outerr_cb_nvim(a:loclist_winid, a:jobid, a:data, a:event, self)
endfunction

function! s:bg_exit_cb_nvim(loclist_winid, jobid, data, event) dict
	if !empty(self.incomplete_line)
		call s:bg_out_cb(a:loclist_winid, a:jobid, self.incomplete_line)
	endif

	let exitcode = a:data
	call s:bg_exit_cb(a:loclist_winid, a:jobid, exitcode)
endfunction

function! s:bg_start(cmd_maybelist, cleanslate, use_loclist, desc, mods)
	let cmd_maybelist = a:cmd_maybelist
	if type(cmd_maybelist) == type('')
		let cmdlist = split(&shell) + split(&shellcmdflag) + [cmd_maybelist]
	else
		let cmdlist = cmd_maybelist
	endif

	if a:use_loclist
		let opencmd = "lopen"
		let loclist_winid = win_getid()
		call setloclist(
		\   0,
		\   [],
		\   a:cleanslate ? ' ' : 'a',
		\   { 'title' : join(cmdlist) }
		\ )
	else
		let opencmd = "copen"
		let loclist_winid = 0
		call setqflist(
		\   [],
		\   a:cleanslate ? ' ' : 'a',
		\   { 'title' : join(cmdlist) }
		\ )
	endif

	let orig_win = winnr()
	exec a:mods . "rightbelow " . opencmd
	if winnr() != orig_win
		wincmd p
	endif

	if has('nvim')
		let opts = {
		\   'on_stdout': function('s:bg_out_cb_nvim', [loclist_winid]),
		\   'on_stderr': function('s:bg_err_cb_nvim', [loclist_winid]),
		\   'on_exit': function('s:bg_exit_cb_nvim', [loclist_winid]),
		\   'incomplete_line': '',
		\}
		let jobid = jobstart(cmdlist, opts)
		if jobid == 0
			throw "invalid job args"
		endif
		if jobid == -1
			throw "couldn't start job"
		endif
		let opts.jobid = jobid
		let handle = jobid
	else
		" out_mode: nl - messages are separated by newline
		let job = job_start(
		\ cmdlist,
		\ {
		\   'out_mode': 'nl',
		\   'in_io': 'null',
		\   'out_cb': function('s:bg_out_cb', [loclist_winid]),
		\   'err_cb': function('s:bg_err_cb', [loclist_winid]),
		\   'exit_cb': function('s:bg_exit_cb', [loclist_winid]),
		\})
		if job_status(job) == 'fail'
			throw "couldn't start job"
		endif
		let handle = job
	endif

	call add(s:jobs, {
	\ 'handle': handle,
	\ 'cmd': cmdlist,
	\ 'desc': a:desc,
	\ 'loclist_winid': loclist_winid,
	\ })
endfunction

function! s:bg_stop(use_loclist)
	let newlist = []

	for job in s:jobs
		if !!job.loclist_winid != a:use_loclist
			call add(newlist, job)
			continue
		endif

		if has('nvim')
			call jobstop(job.handle)
		else
			call job_stop(job.handle)
		endif
	endfor

	let s:jobs = newlist
endfunction

function! s:bg_builtin(builtin, args, cleanslate, use_loclist, mods)
	let desc = a:builtin . ' ' . a:args
	let prg = substitute(a:builtin, '\\$*', a:args, 'g')
	if prg ==# a:builtin
		" no change made - &makeprg (for example) doesn't contain '$*',
		" so we tack on the end:
		let prg .= ' ' . a:args
	endif

	call s:bg_start(prg, a:cleanslate, a:use_loclist, desc, a:mods)
endfunction

function! s:bg_jobs()
	for job in s:jobs
		let windesc = ""
		if job.loclist_winid
			let windesc = " winid: " . job.loclist_winid
		endif
		if has('nvim')
			echo "job: cmd: " . job.desc . windesc
		else
			echo "job: " . job.handle . " cmd: " . job.desc . windesc
		endif
	endfor
endfunction

function! s:bg_clear(use_loclist)
	if a:use_loclist
		call setloclist(0, [])
	else
		call setqflist([])
	endif
endfunction

command! -nargs=+ -complete=shellcmd Bg call s:bg_start(<q-args>, 1, 0, <q-args>, <q-mods>)
command! -nargs=+ -complete=shellcmd Bgl call s:bg_start(<q-args>, 1, 1, <q-args>, <q-mods>)
command! -nargs=+ -complete=shellcmd Bgadd call s:bg_start(<q-args>, 0, 0, <q-args>, <q-mods>)
command! -nargs=+ -complete=shellcmd Bgladd call s:bg_start(<q-args>, 0, 1, <q-args>, <q-mods>)

command! Bgstop call s:bg_stop(0)
command! Bglstop call s:bg_stop(1)

command! Bgjobs call s:bg_jobs()

command! Bgclear call s:bg_clear(0)
command! Bglclear call s:bg_clear(1)

" makeprg and grepprg:
command! -nargs=+ -complete=file Bggrep call s:bg_builtin(&grepprg, <q-args>, 1, 0, <q-mods>)
command! -nargs=+ -complete=file Bglgrep call s:bg_builtin(&grepprg, <q-args>, 1, 1, <q-mods>)
command! -nargs=+ -complete=file Bggrepadd call s:bg_builtin(&grepprg, <q-args>, 0, 0, <q-mods>)
command! -nargs=+ -complete=file Bglgrepadd call s:bg_builtin(&grepprg, <q-args>, 0, 1, <q-mods>)

command! -nargs=* -complete=file Bgmake call s:bg_builtin(&makeprg, <q-args>, 1, 0, <q-mods>)
command! -nargs=* -complete=file Bglmake call s:bg_builtin(&makeprg, <q-args>, 1, 1, <q-mods>)
