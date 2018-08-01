#!/usr/bin/env wish
#
# mcc.tcl --
#
# Multi-channel cross-correlation of teleseismic waveforms
#
# Usage: mcc.tcl shift.dat
#	 shift.dat has (trace arr onOff)
#
# Author: Lupei Zhu	09-20-1999
#

#-------------------procedure definittion------------

source /home/duanyaohui/src/mcc/tcl/SacRead.tcl
source /home/duanyaohui/src/mcc/tcl/plot.tcl


proc main {argc argv} {
    global tscale yscale dy wx tmin tmax maxShift event wrt

    set dy 50
    set wx 900
    set tmin -20
    set tmax  30
    set maxShift 2

    # a frame on the top for holding menus
    frame .top -borderwidth 2 -relief groove
    button .cor  -text Cor -command mcc
    button .quit -text Exit -command {saveOut; exit}
    scale .maxShift -from 0 -to 5 -orient horizont -label "Max Shift" \
            -resolution 0.5 -variable maxShift
    scale .tmin -from -20 -to -1 -orient horizont -label "tmin" \
	    -resolution 1 -variable tmin
    scale .tmax -from 1 -to 80 -orient horizont -label "tmax" \
	    -resolution 1 -variable tmax
    button .scUp -text "Scale Up" -command {scaleTrace 2}
    button .scDn -text "Scale Dn" -command {scaleTrace 0.5}
    button .del -text Delete -command traceDelete
    tk_optionMenu .norm yscale [expr -1.5*$dy] 0.001 0.01 0.1 1 10 100 1e+3 1e+6 1e+9
    button .flip -text "Flip" -command flipTrace
    label .sel -textvariable selected -relief sunken -width 10
    button .master -text "Master" -command makeMaster
    checkbutton .wrt -text "overwrite" -variable wrt -onvalue "-W" -offvalue "" -anchor w

    # a listbox with scroll bar containing event list on the right
    listbox .evelist -width 12 -yscrollcommand ".eveScroll set" \
            -exportselection 0
    scrollbar .eveScroll -command ".evelist yview"

    # canvas for plotting on the left
    canvas .plot -background white -yscrollcommand ".scroll set" \
            -width $wx -height 700 -closeenough 5
    scrollbar .scroll -command ".plot yview" 

    # pack widgets
    pack .top -fill x
    pack .quit .maxShift .cor .wrt .scDn .scUp .del .flip .sel .master .norm .tmin .tmax -side left -in .top
    pack .eveScroll .evelist .scroll .plot -side right -fill y

    # set up the event list from command line
    foreach event $argv {
      .evelist insert end $event
    }
    set event empty

    focus .evelist
    bindtags .evelist {Listbox .evelist}
    bindSel
    bindPlot

}

# bind selection in listbx to ploting
proc bindSel {} {
    bind .evelist <space> drawEvent

    bind .evelist <ButtonRelease-1> drawEvent

    bind .evelist <Return> {
        set indx [.evelist curselection]
        .evelist selection clear $indx
        incr indx
        if {$indx==[.evelist size]} {set indx 0}
        .evelist selection set $indx
	.evelist activate $indx
        .evelist see $indx
        drawEvent
    }
}

# plot bindings
proc bindPlot {} {
    # Button-2 selectes/deselects trace
    .plot bind trace <2> {
	traceSelect current
        set curX %x
	set curY %y
    }

    # Button-1 starts dragging trace
    .plot bind trace <1> {
        set curX %x
	set curY %y
    }

    # drag to move the trace horinzontally
    .plot bind trace <B1-Motion> {
	set stn [lindex [.plot gettags current] 0]
	set delX [expr %x-$curX]
	set delY [expr %y-$curY]
	set arr($stn) [expr ($arr($stn)*$tscale-$delX)/$tscale]
	.plot move  current $delX 0
	set curX %x
	set curY %y
    }

    # Button-1 selectes the time mark
    .plot bind tMark <1> {
	set curX %x
    }

    # drag to move the time mark horinzontally
    .plot bind tMark <B1-Motion> {
	set mark [lindex [.plot gettags current] 0]
	set delX [expr %x-$curX]
	.plot move current $delX 0
	set tWin($mark) [expr ($tWin($mark)*$tscale+$delX)/$tscale]
	set curX %x
    }
}

# plot waveform on the canvas
proc drawEvent {} {
    global tscale yscale wx dy stnList arr onOff tmin tmax event tWin wrt

    # save previous event and clear up the canvas
    if { $event != "empty" } {
	saveOut
        .plot delete trace tMark stnName
    }

    set tscale [expr $wx/($tmax-$tmin)]
    set tWin(before) [expr 0.5*$tmin]
    set tWin(center) 0.
    set tWin(after) [expr 0.5*$tmax]
    set wrt ""
    set event [.evelist get [.evelist curselection]]
    set f [ open $event r ]
    set stnList {}
    while { [gets $f line] >= 0 } {
	scan $line "%s %f %d" stn dum1 dum2
        set arr($stn) $dum1
        set onOff($stn) $dum2
	lappend stnList $stn
    }
    close $f

    set wy [expr $dy*([llength $stnList]+1)]
    .plot configure -scrollregion [list 0 0 $wx $wy]

    # plot three vertical lines for time marks
    foreach mark {before center after} {
        set x [expr ($tWin($mark)-$tmin)*$tscale]
        .plot creat line $x 0 $x $wy -fill blue -tags [list $mark tMark]
    }

    set y $dy
    set stnm 1
    foreach stn $stnList {
	.plot create text 0 $y -text $stn/$stnm -tags [list $stn stnName] \
                -anchor sw
	set temp1 [expr $arr($stn)+$tmin]
	set temp2 [expr $arr($stn)+$tmax]
	set color black
	if {$onOff($stn)==0} {set color red}
	set id [eval tracePlot .plot 0 $y $tscale $yscale $temp1 \
                $stn $color [readSac $stn $temp1 $temp2] ]
	.plot addtag trace withtag $id
	if {$onOff($stn)==0} {.plot addtag sel withtag $stn}
	incr y $dy
	incr stnm
    }

}

# select/de-select trace
proc traceSelect tag {
    global onOff selected
    set selected [lindex [.plot gettags $tag] 0]
    switch [.plot itemcget $tag -fill] {
        black {
            .plot itemconfigure $selected -fill red
	    .plot addtag sel withtag $selected
	    set onOff($selected) 0
        }
        red {
            .plot itemconfigure $selected -fill black
	    .plot dtag $selected sel
	    set onOff($selected) 1
        }
    }
}

# save 
proc saveOut {} {
    global stnList arr onOff event tWin
    set fout [open $event w]
    foreach stn $stnList {
        puts $fout [format "%-6s %9.4f %1d" $stn [expr $tWin(center)+$arr($stn)] $onOff($stn)]
    }
    close $fout
}

# multi-channel cross-correlation 
proc mcc {} {
    global stnList arr event tscale tWin maxShift onOff wrt yscale
    if { $wrt == "-W" && $yscale < 0 } {set nopt "-N"} else { set nopt "" }
    set cmd [open "|src_ss -D$tWin(before)/$tWin(after)/$maxShift $wrt $nopt" r+]
    puts stderr "-----$tWin(before)/$tWin(after)/$maxShift $nopt"
    foreach stn $stnList {
    if { $onOff($stn) != 0 } {
        puts $cmd  "$stn $arr($stn)"
	flush $cmd
	gets $cmd line
	scan $line "%s %s" a1 newArr
	set delX [expr round(($arr($stn)-$newArr)*$tscale)]
	.plot move [lindex [.plot find withtag $stn] 1] $delX 0
	set arr($stn) $newArr
	if { $delX != 0 } {puts stderr "$stn $delX"}
    }
    }
    close $cmd
    if { $wrt == "-W" } plotSRC
}

# change ploting scale
proc scaleTrace mul {
    global dy
    set y $dy
    foreach stn [.plot find withtag trace] {
	.plot scale $stn 0 $y 1 $mul
	incr y $dy
    }
}

# delete marked traces and move traces below up
proc traceDelete {} {
    global dy
    set dely 0
    foreach id [.plot find withtag stnName] {
        set stn [lindex [.plot gettags $id] 0]
        if [lsearch -exact [.plot gettags $id] sel]<0 {
            .plot move $stn 0 $dely
        } else {
            .plot delete $stn
            incr dely -$dy
        }
    }
}

# make the selected trace as the master trace
proc makeMaster {} {
    global selected arr
    puts "cp $selected SRC.s"
    exec cp $selected SRC.s
    set arr(SRC.s) $arr($selected)
    plotSRC
}

# re-plot SRC.s
proc plotSRC {} {
    global dy arr tmin tmax tscale yscale
    set stn SRC.s
    .plot delete $stn
	.plot create text 0 $dy -text $stn -tags [list $stn stnName] \
                -anchor sw
	set temp1 [expr $arr($stn)+$tmin]
	set temp2 [expr $arr($stn)+$tmax]
	set id [eval tracePlot .plot 0 $dy $tscale $yscale $temp1 \
                $stn black [readSac $stn $temp1 $temp2] ]
	.plot addtag trace withtag $id
}

# flip polarities of selected traces
proc flipTrace {} {
    global selected
    set y [lindex [.plot coords [lindex [.plot find withtag $selected] 0]] 1]
    .plot scale $selected 0 $y 1 -1
}

main $argc $argv
