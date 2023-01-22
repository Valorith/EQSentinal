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
our $scan_thread;

my $orange = "\e[38;5;208m";
my $green = "\e[38;5;10m";
my $red = "\e[38;5;9m";
my $reset = "\e[0m";

my @messages = (
"Welcome to the log scanner.",
"Please set the log file path with ${orange}path${reset} command, followed by the full file path to the log file.",
"Once the path is set, start the scanner with the ${orange}start${reset} command.",
"Stop the scanner with the ${orange}stop${reset} command.",
"Enter debug mode with the ${orange}debug${reset} command.",
"Add keywords to search for with the ${orange}add${reset} command, followed by the keyword.",
"Remove keywords from the search list with the ${orange}remove${reset} command, followed by the keyword.",
"List all active keywords by using the ${orange}keywords${reset} command."
);

print join("\n", @messages, "\n");


my $debug = 0;
my $scanning :shared = 0;

sub showKeywords() {
    print "Active keywords: \n";
    foreach my $word (@keywords) {
        print " - $word\n";
    }
}

sub RestartScanner() {
    if (!$log_file) {
        print "Error: Log file path not set. Please set log file path with 'path' command before starting.\n";
    } else {
        if ($scanning) {
            my $stopText = "Stopping current scanning...\n";
            print "$red$stopText$reset";
            $scanning = 0;
            # Wait for previous scan thread to finish
            $scan_thread->join();
        }
        my $startText = "Restarting scanner...\n";
        print "$green$startText$reset";
        $scanning = 1;
        %detected_logs = ();
        my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
        my $startYear = $year + 1900; # year is returned as the number of years since 1900
        my $startMonth = $mon + 1; # month is returned as a number between 0 and 11
        $start_time = DateTime->new(year => $startYear, month => $startMonth, day => $mday, hour => $hour, minute => $min, second => $sec);
        print "Scan start time set at: $start_time\n" if $debug;
        $scan_thread = threads->create(\&scan_log, $log_file, $last_modified);
    }
}


sub main() {
    while (1) {
        my $input = lc(<STDIN>);
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
                    my $startText = "Scanning started\n";
                    print "$green$startText$reset";
                    $scanning = 1;
                    %detected_logs = ();
                    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime();
                    my $startYear = $year + 1900; # year is returned as the number of years since 1900
                    my $startMonth = $mon + 1; # month is returned as a number between 0 and 11

                    $start_time = DateTime->new(year => $startYear, month => $startMonth, day => $mday, hour => $hour, minute => $min, second => $sec);

                    print "Scan start time set at: $start_time\n" if $debug;
                    $scan_thread = threads->create(\&scan_log, $log_file, $last_modified);
                } else {
                    print "Scanning already in progress\n" if $debug;
                }
            }
        } elsif ($input eq "stop") {
            my $stopText = "Scanning stopped\n";
            print "$red$stopText$reset";
            $scanning = 0;
        } elsif ($input eq "debug") {
            $debug = !$debug;
            print "Debugging is ".($debug ? "on" : "off")."\n"
        } elsif ($input =~ /^add (.*)/) {
            push @keywords, $1;
            print "Keyword '$1' added to search list.\n";
            if ($scanning) {
                RestartScanner();
            }
        } elsif ($input =~ /^remove (.)/) {
            my $index = first_index { $_ eq $1 } @keywords;
            if(defined $index) {
                splice @keywords, $index, 1;
                print "Keyword '$1' removed from search list.\n";
                if ($scanning) {
                    RestartScanner();
                }
            } else {
                print "Error: '$1' not found in search list.\n";
            }
        } elsif ($input eq "keywords") {
            showKeywords();
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
            print "Search list keywords: @keywords\n";
            print "Debugging is ".($debug ? "on" : "off")."\n"
        } elsif ($input eq "exit") {
            print "Exiting EQSentinal\n";
            exit;
        } else {
        print "Invalid command. Please enter 'path', 'start', 'stop', 'add', 'remove' or 'status'\n";
        }
    }
}

sub scan_log {
    our ($log_file, $last_modified) = @_;
    # Loop while the scanning variable is true
    while ($scanning) {
        # Get the current modification time of the log file
        my $current_modified = (stat $log_file)[9];
        # Check if the current modification time is greater than the last recorded modification time
        if($current_modified > $last_modified) {
            # Open the log file for reading
            open(my $fh, "<", $log_file) or die "Error opening $log_file: $!";
            # Loop through each line of the log file
            while (my $line = readline $fh) {
                # Loop through each keyword
                for my $keyword (@keywords) {
                    # Check if the keyword appears in the line
                    if ($line =~ /(?i)$keyword/) {
                        # Check if the line has not already been detected
                        if (!exists $detected_logs{$line}) {
                            # Mark the line as detected
                            $detected_logs{$line} = 1;
                            # Call the KeywordDetected function to handle the keyword trigger action
                            KeywordDetected($line, $keyword);
                        }
                    }
                }
            }
            # Update the last recorded modification time
            $last_modified = $current_modified;
            # Close the log file
            close $fh;
        }
    }
}

sub KeywordDetected {
    my ($line, $keyword) = @_;
    # Extracting the date and time from the log line using regular expressions
    my ($log_day, $log_mon, $log_dayOfMonth, $log_hour, $log_min, $log_sec, $log_year) = $line =~ /\[(.*?) (.*?) (.*?) (.*?):(.*?):(.*?) (.*?)\]/;
    # Convert the month and day strings to numerical values
    $log_mon = ConvertMonth($log_mon);
    $log_day = ConvertDay($log_day);
    # Print the extracted date and time parts if the debug flag is set
    print "(LogDay:$log_day, LogMonth:$log_mon, LogDayofMonth:$log_dayOfMonth, LogHour:$log_hour, LogMin:$log_min, LogSec:$log_sec, LogYear:$log_year)\n" if $debug;
    # Create a DateTime object from the extracted date and time parts
    my $log_time = DateTime->new(year => $log_year, month => $log_mon, day => $log_dayOfMonth, hour => $log_hour, minute => $log_min, second => $log_sec);

    # Print the log time and start time if the debug flag is set
    print "LogTime:$log_time, $start_time\n" if $debug;
    # Check if the log time is defined and greater than or equal to the start time
    if (defined($log_time) && ($log_time >= $start_time)) {
        # Place code below to handle keyword trigger actions
        # Print a message indicating that the keyword has been detected in the line
        my $green_line = $line;
        $green_line =~ s/($keyword)/$green$1$reset/g;
        print $log_time->strftime("[%Y-%m-%d %H:%M:%S]"), "Keyword [$green$keyword$reset] detected in line: $green_line\n";
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

main(); #Main sub call