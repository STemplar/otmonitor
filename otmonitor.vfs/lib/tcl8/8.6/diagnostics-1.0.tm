namespace eval diag {
    variable fileevent ""
    namespace export diagnostics

    # Make sure the cursor doesn't move
    foreach n {
	1 Double-1 Triple-1 B1-Motion B1-Enter B1-Leave ButtonRelease-1
    } {
	bind Diag <$n> [namespace code {cursor %W}]
    }
}

proc diag::diagnostics {{version ""}} {
    global dev
    variable text
    if {[info exists dev]} {
	variable fileevent [fileevent $dev readable]
	fileevent $dev readable [list [namespace which receive] $dev]
    }
    toplevel .diag
    place [ttk::frame .diag.bg] -relwidth 1 -relheight 1
    wm title .diag "Opentherm Gateway Diagnostics"
    ttk::frame .diag.f -style TEntry -borderwidth 3
    bind .diag.f <FocusIn> {%W state focus}
    bind .diag.f <FocusOut> {%W state !focus}
    pack .diag.f -fill both -expand y -padx 5 -pady 5
    variable text [text .diag.f.tx -wrap char -font TkFixedFont]
    $text configure -background white -borderwidth 0 -highlightthickness 0
    ttk::scrollbar .diag.f.vs -command [list $text yview]
    $text configure -yscrollcommand {.diag.f.vs set}
    bindtags $text [list $text Diag Text [winfo toplevel $text] all]
    if {[info exists dev]} {
	bind $text <Key> [list [namespace which keypress] $dev %A]
    }
    # Allow selecting and copying the text
    bind $text <<Copy>> {# Fall through}
    bind $text <<SelectAll>> {# Fall through}
    bind $text <Destroy> [list [namespace which finish]]
    grid $text .diag.f.vs -sticky news
    grid columnconfigure [winfo parent $text] $text -weight 1
    grid rowconfigure [winfo parent $text] $text -weight 1
    if {$version ne ""} {
	wm title .diag "Opentherm Gateway Diagnostics"
	$text insert end "Opentherm gateway diagnostics - Version $version\n"
    } else {
	wm title .diag "Diagnostics - requires special firmware"
	if {[info exists dev]} {puts $dev ""}
    }
    $text tag configure bad -foreground red
    $text tag configure note -foreground blue
    $text tag configure fail -foreground purple
    $text mark set last insert
    $text mark gravity last left
    focus $text
}

proc diag::receive {fd} {
    variable text
    if {[eof $fd]} {
	close $fd
	return
    }
    set rec [lassign [split [read $fd] \b] str]
    $text insert end $str
    foreach str $rec {
	$text delete end-2c
	$text insert end $str
    }
    while {[set newline [$text search \n last insert]] ne ""} {
	set line [$text get last $newline]
	if {[scan $line {Opentherm gateway diagnostics - Version %s} ver] == 1} {
	    wm title .diag "Opentherm Gateway Diagnostics"
	} elseif {[regexp {^(\d+,)+\d+\.$} $line]} {
	    timings $line
	}
	$text mark set last $newline+1c
    }
    $text see end
}

proc diag::timings {str} {
    variable text
    scan [$text index last] %d.%d line pos
    set level h
    set error 0
    set bits ""
    foreach n [split [string trimright $str .] ,] {
	if {$n > 400 && $n < 650} {
	    set tag half
	    append bits $level
	} elseif {$n > 900 && $n < 1150} {
	    set tag full
	    if {([string length $bits] % 2) == 0} {
		if {$error == 0} {set error 3}
	    } else {
		append bits $level $level
	    }
	} else {
	    if {$error == 0} {
		if {$n < 500} {
		    set error 1
		} elseif {([string length $bits] % 2) == 0} {
		    set error 3
		} elseif {$n < 1000} {
		    set error 1
		} else {
		    set error 3
		}
	    }
	    set tag bad
	}
	set len [string length $n]
	$text tag add $tag $line.$pos $line.[incr pos $len]
	incr pos
	set level [lindex {h l} [expr {$level eq "h"}]]
    }
    # puts $str
    set binary [string map {hl 1 lh 0} [append bits l]]
    # puts $bits
    # puts $binary
    # puts [format %x [scan [string range $binary 1 32] %b]]
    if {$error != 0} {
    } elseif {[regexp {[lh]} $binary]} {
	set error 3
    } elseif {[scan $binary %*2b%3b%4b%8b%16b%1b type res id data stop] != 5} {
	# Missing bit
	set error 3
    } elseif {$stop != 1} {
	# Wrong stop bit
	set error 2
    } elseif {[llength [regexp -all -inline 1 $binary]] % 2} {
	# Parity error
	set error 4
    } else {
	$text insert $line.$pos \n "" [format "%08X  %-10s  %s: %s" \
	  [scan $binary %*1b%32b] {*}[otdecode data $type $id]] note
    }
    if {$error} {
	$text insert $line.$pos \n "" [format {Error %02d} $error] fail
    }
}

proc diag::keypress {fd char} {
    if {$char ne ""} {
	puts -nonewline $fd $char
	flush $fd
    }
    # Prevent any further processing
    return -code break
}

proc diag::cursor {w} {
    after idle [list $w mark set insert end]
    # after 500 [list $w mark set insert end]
}

proc diag::finish {} {
    global dev
    variable fileevent
    if {[info exists dev] && $dev in [chan names]} {
	fileevent $dev readable $fileevent
    }
}

namespace import diag::*
