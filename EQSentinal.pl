use strict;
use warnings;
use v5.24;
use threads;
use threads::shared;
use Time::Local;
use DateTime;
no warnings 'experimental';

# array of keywords to search for
our @keywords = ("error", "warning", "critical");

# path to log file
our $log_file = undef;
our $last_modified = undef;
our $start_time;
our %detected_logs :shared;

print "Welcome to the log scanner.\n";
print "Please set the log file path with 'path' command, followed by the full file path to the log file.\n";
print "Once the path is set, start the scanner with the 'start' command.\n";
print "Stop the scanner with the 'stop' command.\n";
print "Enter debug mode with the 'debug' command.\n";
my $debug = 0;
my $scanning :shared = 0;

while (1) {
    my $input = <STDIN>;
    chomp $input;
    if ($input =~ /^path (.*)/) {
        $log_file = $1;
        if (-e $log_file) {
            $last_modified = (stat $log_file)[9];
            print "Log file path set to $log_file\n";
        } else {
            print "Error: Log file $log_file does not exist.\n";
            $log_file = undef;
        }
    } elsif ($input eq "start") {
        if (!$log_file) {
            print "Error: Log file path not set. Please set log file path with 'path' command before starting.\n";
        } else {
            if (!$scanning) {
                print "Scanning started\n";
                $scanning = 1;
                %detected_logs = ();
                my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
                my $startYear = $year + 1900; # year is returned as the number of years since 1900
                my $startMonth = $mon + 1; # month is returned as a number between 0 and 11

                $start_time = DateTime->new(year => $startYear, month => $startMonth, day => $mday, hour => $hour, minute => $min, second => $sec);

                print "Scan start time set at: $start_time\n" if $debug;
                my $scan_thread = threads->create(\&scan_log, $log_file, $last_modified);
            } else {
                print "Scanning already in progress\n" if $debug;
            }
        }
    } elsif ($input eq "stop") {
        print "Scanning stopped\n" if $debug;
        $scanning = 0;
    } elsif ($input eq "debug") {
        $debug = !$debug;
        print "Debugging is ".($debug ? "on" : "off")."\n"
    } elsif ($input eq "status") {
        if (!defined($log_file)) {
            print "Log file path not set.\n";
        } else {
            print "Log file path: $log_file\n";
            if ($scanning) {
                print "Scanner status: Running\n";
            } else {
                print "Scanner status: Stopped\n";
            }
        }
        print "Debugging is ".($debug ? "on" : "off")."\n"
    } else {
        print "Invalid command. Please enter 'path', 'start', 'stop' or 'status'\n";
    }
}

sub scan_log {
    our ($log_file, $last_modified) = @_;
    while ($scanning) {
        my $current_modified = (stat $log_file)[9];
        if($current_modified > $last_modified) {
            open(my $fh, "<", $log_file) or die "Error opening $log_file: $!";
            while (my $line = readline $fh) {
                for my $keyword (@keywords) {
                    if ($line =~ /(?i)$keyword/) {
                        if (!exists $detected_logs{$line}) {
                            $detected_logs{$line} = 1;
                            KeywordDetected($line, $keyword);
                        }
                    }
                }
            }
            $last_modified = $current_modified;
            close $fh;
        }
    }
}


sub KeywordDetected {
    my ($line, $keyword) = @_;
    my ($log_day, $log_mon, $log_dayOfMonth, $log_hour, $log_min, $log_sec, $log_year) = $line =~ /\[(.*?) (.*?) (.*?) (.*?):(.*?):(.*?) (.*?)\]/;
    $log_mon = ConvertMonth($log_mon);
    $log_day = ConvertDay($log_day);
    print "(LogDay:$log_day, LogMonth:$log_mon, LogDayofMonth:$log_dayOfMonth, LogHour:$log_hour, LogMin:$log_min, LogSec:$log_sec, LogYear:$log_year)\n" if $debug;
    my $log_time = DateTime->new(year => $log_year, month => $log_mon, day => $log_dayOfMonth, hour => $log_hour, minute => $log_min, second => $log_sec);

    if ($log_time >= $start_time) {
        print "LogTime:$log_time >= $start_time\n" if $debug;
    } else {
        print "LogTime:$log_time < $start_time\n" if $debug;
    }
    print "LogTime:$log_time, $start_time\n" if $debug;
    if (defined($log_time) && ($log_time >= $start_time)) {
        #Place code below to handle keyword trigger actions
        print $log_time->strftime("[%Y-%m-%d %H:%M:%S]"), " Keyword [$keyword] detected in line: $line\n";
    }
}








sub ConvertMonth {
	my $month = lc(shift);
	
	if ($month eq "jan") { return 1; }
	elsif ($month eq "feb") { return 2; }
	elsif ($month eq "mar") { return 3; }
	elsif ($month eq "apr") { return 4; }
	elsif ($month eq "may") { return 5; }
	elsif ($month eq "jun") { return 6; }
	elsif ($month eq "jul") { return 7; }
	elsif ($month eq "aug") { return 8; }
	elsif ($month eq "sep") { return 9; }
	elsif ($month eq "oct") { return 10; }
	elsif ($month eq "nov") { return 11; }
	elsif ($month eq "dec") { return 12; }
	else { return 0; }
}

sub ConvertDay {
	my $day = lc(shift);
	
	given ($day) {
		when ("mon") { return 1; }
		when ("tue") { return 2; }
		when ("wed") { return 3; }
		when ("thu") { return 4; }
		when ("fri") { return 5; }
		when ("sat") { return 6; }
		when ("sun") { return 7; }
		default { return 0; }
	}
}

