#!/usr/bin/env perl
# Given a tagtime log file, a Beeminder graph to update, and the list of tagtime
# tags to include in the beeminder graph (only tagtime pings with one of those 
# tags will be included), call the Beeminder API to update the graph.
# As a side effect, generate a .bee file from a tagtime log and existing bee 
# file, if any. (The .bee file is used as a cache to avoid calling the Beeminder
# API if the tagtime log changed but it did not entail any changes relevant to 
# the given Beeminder graph.
# Exception / special case: if the graph is called "nafk" then count pings 
# that *don't* match. (That's for tracking time at the computer, ie, not afk.)

require "$ENV{HOME}/.tagtimerc";

$ping = ($gap+0.0)/3600;  # number of hours per ping.

die "usage: ./beeminder.pl tagtimelog user/slug <tags>" if (@ARGV < 3);

$tplf = shift;  # tagtime log filename.
$usrslug = shift;
$usrslug =~ /^(?:.*?(?:\.\/)?data\/)?([^\+\/\.]*)[\+\/]([^\.]*)/;
($usr, $slug) = ($1, $2);
$beef = "$usr+$slug.bee"; # beef = bee file
@tag = @ARGV;

$beedata0 = "";  # original bee data.
$beedata1 = "";  # new bee data.

if(-e $beef) {
  $beedata0 = do {local (@ARGV,$/) = $beef; <>}; # slurp file into string
}

open(T, $tplf) or die;
$i = 0;
while(<T>) {
  if(!/^(\d+)\s*(.*)$/) { die; }
  my $ts = $1;
  my $stuff = $2;
  my $tags = strip($stuff);

  for my $t (@tag) {
    if($ts>=$start && ($slug ne "nafk" && $tags=~/\b$t\b/ || 
                       $slug eq "nafk" && $tags!~/\b$t\b/)) {
      my($yr,$mo,$d,$h,$m,$s) = dt($ts);
      $pinghash{"$yr-$mo-$d"} += 1; 
      $stuffhash{"$yr-$mo-$d"} .= stripb($stuff) . ", ";
      $i++;
      last;  
    }
  }
}
close(T);

$n = scalar(keys(%pinghash));
$i = 1;
for(sort(keys(%pinghash))) {
  ($yr, $mo, $d) = /^(\d+)\-(\d+)\-(\d+)$/;
  $stuffhash{$_} =~ s/\s*(\||\,)\s*$//;
  $beedata1 .= "$yr $mo $d  ".$pinghash{$_}*$ping." \"".
               splur($pinghash{$_},"ping").   
               # this makes the bee file change every time, which means 
               #   unneccesary regenerating of graphs:
               #($i==$n ? " @ ".ts(time) : "").
               ": ".$stuffhash{$_}."\"\n";
  $i++;
}

if($beedata0 ne $beedata1) {
  #print "DEBUG: calling beemapi tagtime_update tgt $usr $slug\n";
  open(G, "|${path}beemapi.rb tagtime_update tgt $usr $slug") or die;
  print G "$beedata1";
  close(G);
  open(K, ">$beef") or die "Can't open $beef: $!"; # spew the string
  print K $beedata1;                               # $beedata1 to
  close(K);                                        # the file $beef
}

print "Pings with", ($slug eq "nafk" ? "OUT" : ""), 
  " tags {", join(", ", @tag), "}: $i.\n";

# Singular or Plural:  Pluralize the given noun properly, if n is not 1. 
#   Eg: splur(3, "boy") -> "3 boys"
sub splur { my($n, $noun) = @_;  return "$n $noun".($n==1 ? "" : "s"); }

# round to nearest integer.
sub round1 { my($x) = @_; return int($x + .5 * ($x <=> 0)); }
sub round3 { my($x) = @_; return round1($x*1000)/1000; }


# Strips out stuff in parens and brackets; remaining parens/brackets means
#  they were unmatched.   
sub strip {
  my($s)=@_;
  while($s =~ s/\([^\(\)]*\)//g) {}
  while($s =~ s/\[[^\[\]]*\]//g) {}
  $s;
}

# Strips out stuff in brackets only; remaining brackets means
#  they were unmatched.   
sub stripb {
  my($s)=@_;
  while($s =~ s/\s*\[[^\[\]]*\]//g) {}
  $s;
}

# Fetches stuff in parens. 
sub fetchp {
  my($s)=@_;
  my $tmp = $s;
  while($tmp =~ s/\([^\(\)]*\)/UNIQUE78DIV/g) {}
  my @a = split('UNIQUE78DIV', $tmp);
  for(@a) {
    my $i = index($s, $_);
    substr($s, $i, length($_)) = "";
  }
  $s =~ s/^\(//;
  $s =~ s/\)$//;
  return $s;
}

# Date/time: Takes unix time (seconds since 1970-01-01 00:00:00 GMT) and 
# returns list of
#   year, mon, day, hr, min, sec, day-of-week, day-of-year, is-daylight-time
sub dt { my($t) = @_;
  $t = time unless defined($t);
  my($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($t);
  $year += 1900;  $mon = dd($mon+1);  $mday = dd($mday);
  $hour = dd($hour);  $min = dd($min); $sec = dd($sec);
  my %wh = ( 0=>"SUN",1=>"MON",2=>"TUE",3=>"WED",4=>"THU",5=>"FRI",6=>"SAT" );
  return ($year,$mon,$mday,$hour,$min,$sec,$wh{$wday},$yday,$isdst);
}

# Time string: takes unix time and returns a formated YMD HMS string.
sub ts { my($t) = @_;
  my($year,$mon,$mday,$hour,$min,$sec,$wday,$yday,$isdst) = dt($t);
  return "$year-$mon-$mday $hour:$min:$sec $wday";
} 

# double-digit: takes number from 0-99, returns 2-char string eg "03" or "42".
sub dd { my($n) = @_;  return padl($n, "0", 2); }
  # simpler but less general version: return ($n<=9 && $n>=0 ? "0".$n : $n)

# pad left: returns string x but with p's prepended so it has width w
sub padl {
  my($x,$p,$w)= @_;
  if (length($x) >= $w) { return substr($x,0,$w); }
  return $p x ($w-length($x)) . $x;
}

