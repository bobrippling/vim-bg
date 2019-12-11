let s:jobs = []

function! s:bg_append(line)
	let line = a:line
	let line = substitute(line, '\r$', '', 'g')
	caddexpr line
endfunction

function! s:bg_exit_cb(job, exitcode)
	let i = 0
	for job in s:jobs
		if job.handle == a:job
			call s:bg_append('--- ' . job.desc . ' exited with ' . a:exitcode . ' ---')
			call remove(s:jobs, i)
			break
		endif
		let i = i + 1
	endfor
endfunction

function! s:bg_out_cb(ch, line)
	" standard out
	call s:bg_append(a:line)
endfunction

function! s:bg_err_cb(ch, line)
	" standard error
	call s:bg_append(a:line)
endfunction

function! s:bg_outerr_cb_nvim(jobid, data, event, self)
	" let eof = (a:data == [''])

	let a:self.incomplete_line .= a:data[0]

	" we've completed the last line
	if !empty(a:self.incomplete_line)
		call s:bg_out_cb(a:jobid, a:self.incomplete_line)
	endif

	for ent in a:data[1:-2]
		call s:bg_out_cb(a:jobid, ent)
	endfor

	let a:self.incomplete_line = a:data[-1]
endfunction

function! s:bg_out_cb_nvim(jobid, data, event) dict
	call s:bg_outerr_cb_nvim(a:jobid, a:data, a:event, self)
endfunction

function! s:bg_err_cb_nvim(jobid, data, event) dict
	call s:bg_outerr_cb_nvim(a:jobid, a:data, a:event, self)
endfunction

function! s:bg_exit_cb_nvim(jobid, data, event) dict
	if !empty(self.incomplete_line)
		call s:bg_out_cb(a:jobid, self.incomplete_line)
	endif

	let exitcode = a:data
	call s:bg_exit_cb(a:jobid, exitcode)
endfunction

function! s:bg_start(cmd_maybelist, cleanslate, desc, mods)
	let cmd_maybelist = a:cmd_maybelist
	if type(cmd_maybelist) == type('')
		let cmdlist = split(&shell) + split(&shellcmdflag) + [cmd_maybelist]
	else
		let cmdlist = cmd_maybelist
	endif

	call setqflist(
	\   [],
	\   a:cleanslate ? ' ' : 'a',
	\   { 'title' : join(cmdlist) }
	\ )

	if empty(a:mods)
		rightbelow copen
	else
		exec a:mods "copen"
	endif
	wincmd p

	if has('nvim')
		let opts = {
		\   'on_stdout': function('s:bg_out_cb_nvim'),
		\   'on_stderr': function('s:bg_err_cb_nvim'),
		\   'on_exit': function('s:bg_exit_cb_nvim'),
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
		\   'out_cb': function('s:bg_out_cb'),
		\   'err_cb': function('s:bg_err_cb'),
		\   'exit_cb': function('s:bg_exit_cb'),
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
	\ })
endfunction

function! s:bg_stop()
	for job in s:jobs
		if has('nvim')
			call jobstop(job.handle)
		else
			call job_stop(job.handle)
		endif
	endfor
	let s:jobs = []
endfunction

function! s:bg_builtin(builtin, args, cleanslate, mods)
	let desc = a:builtin . ' ' . a:args
	let prg = substitute(a:builtin, '\\$*', a:args, 'g')
	if prg ==# a:builtin
		" no change made - &makeprg (for example) doesn't contain '$*',
		" so we tack on the end:
		let prg .= ' ' . a:args
	endif

	call s:bg_start(prg, a:cleanslate, desc, a:mods)
endfunction

function! s:bg_jobs()
	for job in s:jobs
		if has('nvim')
			echo "job: cmd: " . job.desc
		else
			echo "job: " . job.handle . " cmd: " . job.desc
		endif
	endfor
endfunction

function! s:bg_clear()
	call setqflist([])
endfunction

command! -nargs=+ -complete=shellcmd Bg call s:bg_start(<q-args>, 1, <q-args>, <q-mods>)
command! -nargs=+ -complete=shellcmd Bgadd call s:bg_start(<q-args>, 0, <q-args>, <q-mods>)

command! Bgstop call s:bg_stop()

command! Bgjobs call s:bg_jobs()

command! Bgclear call s:bg_clear()

" makeprg and grepprg:
command! -nargs=+ -complete=file Bggrep call s:bg_builtin(&grepprg, <q-args>, 1, <q-mods>)
command! -nargs=+ -complete=file Bggrepadd call s:bg_builtin(&grepprg, <q-args>, 0, <q-mods>)

command! -nargs=* -complete=file Bgmake call s:bg_builtin(&makeprg, <q-args>, 1, <q-mods>)
