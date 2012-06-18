! Copyright (C) 2012 Your name.
! See http://factorcode.org/license.txt for BSD license.
USING: ;
IN: cpuguard

USING: io.directories kernel math.parser sequences splitting locals io.encodings.binary io.encodings.ascii io.files math arrays threads calendar assocs accessors io  prettyprint unix.process ;

! **** Generic API
: clone* ( x -- x y ) dup clone ; inline
: if*_empty? ( arr quott quotf -- x ) [ dup empty? ] 2dip if ; inline
: tokens ( string -- tokens ) " " split [ "" = not ] filter ;
: numeric? ( string -- ? ) string>number >boolean ;

! **** pid API
:: pid_file ( pid file -- result ) { "/proc" pid file } "/" join ;
: pid_cmdline ( pid -- cmdline ) "cmdline" pid_file ascii file-lines [ ] [ first "\0" split ] if*_empty? ;
: pids ( -- pids ) "/proc" directory-files [ numeric? ] filter ;
: pid_limits ( pid -- lim ) 
    dup pid_cmdline [ 2drop f ] [ first "python" = [ 5 40 2array 2array ] [ drop f ] if ] if*_empty? ;
: limits_with_pids ( -- limits pids ) pids  [ pid_limits ] map [ ] filter unzip swap ;
: pid_stat ( pid -- stat ) "stat" pid_file binary file-contents tokens ;
: pid_time ( pid -- time ) pid_stat [ 13 14 ] dip [ nth string>number ] curry bi@ + ;
: total_time ( -- time ) "/proc/stat" ascii file-lines first tokens rest [ string>number ] map sum ;
: pid_and_total_time ( pid -- pair ) pid_time total_time 2array ;
: cpu_usage_from_pairs ( pair1 pair2 -- usage ) swap [ - ] 2map first2 / 100 * ;

! **** phase class API
TUPLE: phase_state arr1 arr2 counts ;
: <phase_state> ( -- ps ) phase_state new 65536 0 <array>       >>counts 
                                          65536 { 0 0 } <array> >>arr2 
                                          65536 { 0 0 } <array> >>arr1 ;
: nth_cpu_usage ( n ps -- usage ) [ arr1>> ] [ arr2>> ] bi pick swap [ nth ] 2bi@ cpu_usage_from_pairs ;
: arr2>arr1 ( ps1 -- ps2 ) dup arr2>> clone >>arr1 ;


! **** phase runner API
: update_arr2 ( arr2 pids -- ) [ dup pid_and_total_time swap string>number pick set-nth ] each drop ;
: who_used_cpu ( ps limits pids -- limits2 pids2 ) zip 
                                                   [ first2 [ second ] dip string>number pick nth_cpu_usage < ] filter
                                                   unzip
                                                   [ drop ] 2dip ;
: increase_counts ( counts pids -- ) [ string>number [ over nth 1 + ] keep pick set-nth ] each drop ;
: pids_to_kill ( counts limits pids -- pids2 ) zip 
                                               [ first2 [ first ] dip string>number pick nth < ] filter 
                                               unzip
                                               [ 2drop ] dip ;
: kill_pids ( pids -- ) [ string>number 9 kill drop ] each ;
: phase ( ps1 -- ps2 ) limits_with_pids                                                     ! ps1    limits pids
                       [ pick arr2>> swap update_arr2 ] keep                                ! ps1.5  limits pids     
                       [ dup ] 2dip who_used_cpu                                            ! ps1.5  limits2 pids2
                       [ over counts>> ] dip [ increase_counts ] keep                       ! ps1.75 limits2 pids2
                       [ dup counts>> ] 2dip pids_to_kill                                   ! ps1.75 pids3
                       kill_pids arr2>arr1 1 seconds sleep phase ;

! **** main entrypoint
: cpuguard ( -- x ) <phase_state> phase ;

