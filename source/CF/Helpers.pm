#!/usr/bin/perl
package CF::Helpers; 

use warnings;
use strict;
use FindBin qw($Bin);
use Exporter;
use POSIX qw(strftime);
use Data::Dumper;

sub load_runfile_params {
	my ($runfile, $job_id, $prev_job_id, $cores, $mem, @parameters) = @_;
	unless (defined $prev_job_id && length($prev_job_id) > 0) {
		die "Previous job ID not specified\n";
	}
	unless (@parameters) {
		@parameters = ();
	}
	
	my $num_input_files = 0;
	
	my $date = strftime "%H:%M, %d-%m-%Y", localtime;
	my $dashes = "-" x 80;
	warn "\n$dashes\nRun File:\t\t$runfile\nJob ID:\t\t\t$job_id\nPrevious Job ID:\t$prev_job_id\nParameters:\t\t".join(", ", @parameters)."\nDate & Time:\t\t$date\n$dashes\n\n";

	open (RUN,$runfile) or die "Can't read $runfile: $!";

	my @files;
	my %config;
	my $comment_block = 0;
	while(<RUN>){
	
		# clean up line
		chomp;
		s/\n//;
		s/\r//;
		
		# Ignore comment blocks
		if($_ =~ /^\/\*/){
			$comment_block = 1;
			next;
		}
		if($_ =~ /^\*\//){
			$comment_block = 0;
			next;
		}
		
		# Get config variables
		if($_ =~ /^\@/ && !$comment_block){
			my @sections = split(/\t/, $_, 2);
			my $cname = substr($sections[0], 1);
			$config{$cname} = $sections[1];
		}
		
		# Get files
		if($_ =~ /^[^@#]/ && !$comment_block){
			my @sections = split(/\t/, $_, 2);
			if($sections[0] eq $prev_job_id){
				# Clear out excess whitespace
				$sections[1] =~ s/^\s+//;
				$sections[1] =~ s/\s+$//;
				# Push to array
				push(@files, $sections[1]);
				$num_input_files++;
			}
		}
	}
	
	close(RUN);
	
	# If we don't have any input files, bail now
	if($num_input_files == 0 && $prev_job_id ne 'null'){
		print "\n###  Error - no file names found from job $prev_job_id. Exiting... ###\n\n";
		exit;
	}
	
	return (\@files, $runfile, $job_id, $prev_job_id, $cores, $mem, \@parameters, \%config);
}


# Function to look at supplied file names and work out whether they're paired end or not
sub is_paired_end {
	
	my @files = sort(@_);
	my @se_files;
	my @pe_files;
	
	for (my $i = 0; $i <= $#files; $i++){
		if($i < $#files){
			# Make stripped copies of the fns for comparison
			(my $fn1 = $files[$i]) =~ s/_[1-4]//g;
			(my $fn2 = $files[$i+1]) =~ s/_[1-4]//g;
			if($fn1 eq $fn2){
				my @pe = ($files[$i], $files[$i+1]);
				push (@pe_files, \@pe);
				$i++; # Push up $i so we ignore the next file
			} else {
				push (@se_files, $files[$i]);
			}
		} else {
			# If we have an odd number of file names and have got to the end, must be SE
			push (@se_files, $files[$i]);
		}
	}
	
	return (\@se_files, \@pe_files);
}


# Function to look into BAM/SAM header to see whether it's paired end or not
sub is_bam_paired_end {

	my ($file) = @_;
	
	unless($file =~ /.bam$/ || $file =~ /.sam$/){
		warn "\n$file is not a .bam or .sam file - can't figure out PE / SE mode..\nExiting..\n\n";
		die;
	}
	
	my $headers = `samtools view -H $file`;
	
	my $paired_end;
	my $header_found;
	foreach (split("\n", $headers)){
		if(/^\@PG/){
			if(/-1/ && /-2/){
				$paired_end = 1;
				$header_found = 1;
			} else {
				$paired_end = 0;
				$header_found = 1;
			}
		}
	}
	
	if(!$header_found){
		warn "\nCould not find BAM \@PG header, so could not determine read type.\nExiting...\n\n";
		die;
	}
	
	return $paired_end;
	
}

# Function to determine the encoding of a FastQ file (nicked from HiCUP)
# See http://en.wikipedia.org/wiki/FASTQ_format#Encoding
# phred33: ASCII chars begin at 33
# phred64: ASCII chars begin at 64
# solexa: ASCII chars begin at 59
# integer: quality values integers separated by spaces
sub fastq_encoding_type {

	my $file = $_[0];
	my $score_min = 999;    #Initialise at off-the-scale values
	my $score_max = -999;
	my $read_count = 0;
	
	if($file =~ /\.gz$/){
		open (IN, "zcat $file |") or die "Could not read file '$file' : $!";
	} else {
		open (IN, $file) or die "Could not read file '$file' : $!";
	}
	
	while(<IN>){
	
		if(/^@/){	# Start with an @ symbol - read identifier
			
			# push file counter on two lines to the quality score
			scalar <IN>;
			scalar <IN>; 
			
			my $quality_line = scalar <IN>;
			chomp $quality_line;    
			my @scores = split(//, $quality_line);
			
			foreach(@scores){
				my $score = ord $_;    #Determine the value of the ASCII character
				
				if($score < $score_min){
					$score_min = $score;
				}
				if($score > $score_max){
					$score_max = $score;
				}	
			}
		
			#Do not need to process 100,000 lines if these parameters are met
			if($score_min == 32){    # Contains the space charcter
				return 'integer';
			} elsif ($score_min < 59){   # Contains low range character
				return 'phred33';
			} elsif ( ($score_min < 64) and ($score_max > 73) ){	# Contains character below phred64 and above phred33
				return 'solexa'
			}
			
			$read_count++;
		}
		
	}
	close IN;
	
	if($read_count < 100000){
		return 0;    #File did not contain enough lines to make a decision on quality
	} else {
		return 'phred64';
	}
}















1; # Must return a true value