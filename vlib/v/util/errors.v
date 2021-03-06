// Copyright (c) 2019-2020 Alexander Medvednikov. All rights reserved.
// Use of this source code is governed by an MIT license
// that can be found in the LICENSE file.
module util

import os
import term
import v.token
import time

// The filepath:line:col: format is the default C compiler error output format.
// It allows editors and IDE's like emacs to quickly find the errors in the
// output and jump to their source with a keyboard shortcut.
// NB: using only the filename may lead to inability of IDE/editors
// to find the source file, when the IDE has a different working folder than
// v itself.
// error_context_before - how many lines of source context to print before the pointer line
// error_context_after - ^^^ same, but after
const (
	error_context_before = 2
	error_context_after  = 2
)

// emanager.support_color - should the error and other messages
// have ANSI terminal escape color codes in them.
// By default, v tries to autodetect, if the terminal supports colors.
// Use -color and -nocolor options to override the detection decision.
pub const (
	emanager = new_error_manager()
)

pub struct EManager {
mut:
	support_color bool
}

pub fn new_error_manager() &EManager {
	return &EManager{
		support_color: term.can_show_color_on_stderr()
	}
}

pub fn (e &EManager) set_support_color(b bool) {
	e.support_color = b
}

fn bold(msg string) string {
	if !emanager.support_color {
		return msg
	}
	return term.bold(msg)
}

fn color(kind, msg string) string {
	if !emanager.support_color {
		return msg
	}
	if kind.contains('error') {
		return term.red(msg)
	} else {
		return term.magenta(msg)
	}
}

// formatted_error - `kind` may be 'error' or 'warn'
pub fn formatted_error(kind, omsg, filepath string, pos token.Position) string {
	emsg := omsg.replace('main.', '')
	mut path := filepath
	verror_paths_override := os.getenv('VERROR_PATHS')
	if verror_paths_override == 'absolute' {
		path = os.real_path(path)
	} else {
		// Get relative path
		workdir := os.getwd() + os.path_separator
		if path.starts_with(workdir) {
			path = path.replace(workdir, '')
		}
	}
	//
	source := read_file(filepath) or {
		''
	}
	mut p := imax(0, imin(source.len - 1, pos.pos))
	if source.len > 0 {
		for ; p >= 0; p-- {
			if source[p] == `\r` || source[p] == `\n` {
				break
			}
		}
	}
	column := imax(0, pos.pos - p - 1)
	position := '${path}:${pos.line_nr+1}:${util.imax(1,column+1)}:'
	scontext := source_context(kind, source, column, pos).join('\n')
	final_position := bold(position)
	final_kind := bold(color(kind, kind))
	final_msg := emsg
	final_context := if scontext.len > 0 { '\n$scontext' } else { '' }
	//
	return '$final_position $final_kind $final_msg $final_context'.trim_space()
}

pub fn source_context(kind, source string, column int, pos token.Position) []string {
	mut clines := []string{}
	if source.len == 0 {
		return clines
	}
	source_lines := source.split_into_lines()
	bline := imax(0, pos.line_nr - error_context_before)
	aline := imax(0, imin(source_lines.len - 1, pos.line_nr + error_context_after))
	tab_spaces := '    '
	for iline := bline; iline <= aline; iline++ {
		sline := source_lines[iline]
		start_column := imin(column, sline.len)
		end_column := imin(column + pos.len, sline.len)
		cline := if iline == pos.line_nr {
			sline[..start_column] + color(kind, sline[start_column..end_column]) + sline[end_column..]
		} else {
			sline
		}
		clines << '${iline+1:5d} | ' + cline.replace('\t', tab_spaces)
		//
		if iline == pos.line_nr {
			// The pointerline should have the same spaces/tabs as the offending
			// line, so that it prints the ^ character exactly on the *same spot*
			// where it is needed. That is the reason we can not just
			// use strings.repeat(` `, col) to form it.
			mut pointerline := ''
			for bchar in sline[..start_column] {
				x := if bchar.is_space() {
					bchar
				} else {
					` `
				}
				pointerline += x.str()
			}
			underline := if pos.len > 1 {
				'~'.repeat(end_column - start_column)
			} else {
				'^'
			}
			pointerline += bold(color(kind, underline))
			clines << '      | ' + pointerline.replace('\t', tab_spaces)
		}
	}
	return clines
}

pub fn verror(kind, s string) {
	final_kind := bold(color(kind, kind))
	eprintln('${final_kind}: $s')
	exit(1)
}

pub fn find_working_diff_command() ?string {
	for diffcmd in ['colordiff', 'gdiff', 'diff', 'colordiff.exe', 'diff.exe'] {
		p := os.exec('$diffcmd --version') or {
			continue
		}
		if p.exit_code == 0 {
			return diffcmd
		}
	}
	return error('no working diff command found')
}

pub fn color_compare_files(diff_cmd, file1, file2 string) string {
	if diff_cmd != '' {    	
		mut other_options := os.getenv('VDIFF_OPTIONS')
		full_cmd := '$diff_cmd --minimal --text --unified=2 ' +
		        ' --show-function-line="fn " $other_options "$file1" "$file2" '
		x := os.exec(full_cmd) or {
			return 'comparison command: `${full_cmd}` failed'
        }
        return x.output.trim_right('\r\n')
    }
    return ''
}

pub fn color_compare_strings(diff_cmd string, expected string, found string) string {
	cdir := os.cache_dir()
	ctime := time.sys_mono_now()
	e_file := os.join_path(cdir, '${ctime}.expected.txt')
	f_file := os.join_path(cdir, '${ctime}.found.txt')
	os.write_file( e_file, expected)
	os.write_file( f_file, found)
	res := util.color_compare_files(diff_cmd, e_file, f_file)
	os.rm( e_file )
	os.rm( f_file )
	return res
}
