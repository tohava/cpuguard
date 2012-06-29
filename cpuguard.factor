! Copyright (C) 2012 Your name.
! See http://factorcode.org/license.txt for BSD license.
IN: cpuguard

USING: io.directories kernel math.parser sequences splitting locals io.encodings.binary io.encodings.ascii io.files math arrays threads calendar assocs accessors io  prettyprint unix.process io.launcher ;

! **** Generic API
: clone* ( x -- x y ) dup clone ; inline
: if*-empty? ( arr true false -- x ) [ dup empty? ] 2dip if ; inline
: tokens ( string -- tokens ) " " split harvest ;

! **** pid API
:: pid-file ( pid file -- result ) { "/proc" pid file } "/" join ;
: pid-cmdline ( pid -- cmdline ) "cmdline" pid-file ascii file-lines [ ] [ first "\0" split ] if*-empty? ;
: pids ( -- pids ) "/proc" directory-files [ string>number ] filter ;
: pid-limits ( pid -- lim ) 
    dup pid-cmdline [ 2drop f ] [ first "python" = [ 5 40 2array 2array ] [ drop f ] if ] if*-empty? ;
: limits-with-pids ( -- limits pids ) pids  [ pid-limits ] map sift unzip swap ;
: pid-stat ( pid -- stat ) "stat" pid-file binary file-contents tokens ;
: pid-time ( pid -- time ) pid-stat [ 13 14 ] dip [ nth string>number ] curry bi@ + ;
: total-time ( -- time ) "/proc/stat" ascii file-lines first tokens rest [ string>number ] map sum ;
: pid-and-total-time ( pid -- pair ) pid-time total-time 2array ;
: cpu-usage-from-pairs ( pair1 pair2 -- usage ) swap [ - ] 2map first2 / 100 * ;
: pid-pretty-print ( pid -- str ) " - " over pid-cmdline first append append ;


! **** phase class API
TUPLE: phase-state arr1 arr2 counts ;
: <phase-state> ( -- ps ) phase-state new 65536 0 <array>       >>counts 
                                          65536 { 0 0 } <array> >>arr2 
                                          65536 { 0 0 } <array> >>arr1 ;
: nth-cpu-usage ( n ps -- usage ) [ arr1>> nth ] [ arr2>> nth ] bi-curry bi cpu-usage-from-pairs ;
: arr2>arr1 ( ps1 -- ps2 ) dup arr2>> clone >>arr1 ;


! **** phase runner API
: update-arr2 ( arr2 pids -- ) [ [ pid-and-total-time ] [ string>number ] bi pick set-nth ] each drop ;
: who-used-cpu ( ps limits pids -- limits2 pids2 ) zip 
                                                   [ first2 [ second ] dip string>number pick nth-cpu-usage < ] filter
                                                   unzip
                                                   [ drop ] 2dip ;
: increase-counts ( counts pids -- ) [ string>number [ over nth 1 + ] keep pick set-nth ] each drop ;
: pids-to-kill ( counts limits pids -- pids2 ) zip 
                                               [ first2 [ first ] dip string>number pick nth < ] filter 
                                               unzip
                                               [ 2drop ] dip ;
: notify-kill ( pids -- pids )
    dup empty?
    [ "notify-send -u critical \"cpuguard kills\" \"" 
       over [ pid-pretty-print ] map "\n" join
      "\"" append append dup . run-process wait-for-process drop ] 
    unless ;

: kill-pids ( pids -- ) 
    notify-kill
    [ string>number 9 kill drop ] each ;

: phase ( ps1 -- ps2 ) "limits-with-pids" print limits-with-pids                                                     ! ps1    limits pids
                       "update-arra2" print     [ pick arr2>> swap update-arr2 ] keep                                ! ps1.5  limits pids     
                       "who-used-cpu" print     [ dup ] 2dip who-used-cpu                                            ! ps1.5  limits2 pids2
                       "increase-counts" print  [ over counts>> ] dip [ increase-counts ] keep                       ! ps1.75 limits2 pids2
                       "pids-to-kill" print     [ dup counts>> ] 2dip pids-to-kill                                   ! ps1.75 pids3
                       "kill-pids" print        kill-pids arr2>arr1 1 seconds sleep phase ;

! **** main entrypoint
: cpuguard ( -- x ) <phase-state> phase ;

!  MAIN: cpuguard