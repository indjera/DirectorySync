#!/usr/bin/perl
package get_diff_files_tar;
use strict;
use Archive::Tar;
use threads;
use threads::shared;
use IO::Socket;
use File::Copy ;
use File::Copy "cp";
use POSIX 'setsid';
use File::Path;
sub daemonize {
            #   chdir '/'               or die "Can't chdir to /: $!";
               open STDIN, '/dev/null' or die "Can't read /dev/null: $!";
               open STDOUT, '>/dev/null'
                                       or die "Can't write to /dev/null: $!";
               defined(my $pid = fork) or die "Can't fork: $!";
               exit if $pid;
               setsid                  or die "Can't start a new session: $!";
               open STDERR, '>&STDOUT' or die "Can't dup stdout: $!";
           }


sub new {
	my $self={};
	bless $self,"get_diff_files_tar";
	return $self;
	
}

sub swap_files{
		
	open (FILL,"<","Archive/filelist") or die("$!");
	my @filelist=<FILL>;
	map chomp,@filelist;
	for(@filelist){
		(-d "Archive/$_")? mkdir $_:move("Archive/$_",$_) ;
	}
	 
       close FILL;
       rmtree ("Archive");   # може да е в коментар
	
}
sub delfile{
	
	if(-e "dellist"){
		
		open (FFF,"<","dellist");
		my @dellist=<FFF>;
		for(@dellist){unlink $_;}
	}
}
sub extractArchive {
    shift;
    my $tarname=shift;
     if(-e $tarname){
	
        my $tar=Archive::Tar->new;
	$tar->read($tarname);
	if(!(-e "Archive"|| -d "Archive")){mkdir "Archive"; }
	chdir "Archive";
	$tar->extract();
	chdir "..";
	unlink "Archive.tgz" ;  # може да е в коментар
	swap_files;
	
	}
  
}

sub connect_to_server {
	my $ok;
	my $server='localhost';
	#print "Connecting to $server:6666...\n";
	my $socket=IO::Socket::INET->new (
		Proto=>'tcp',
		PeerAddr=>$server,
		PeerPort=>'6666'
	)or $ok=-1 ;
	
	$ok=<$socket>;
	if($ok>0){cp ($socket , "Archive.tgz");}
	close ($socket) if $ok== -1;
}
sub connect_clock {
    my $self=shift;
    my $thr=threads->new(sub {
        
                 while(1){
			
                   connect_to_server;
		   extractArchive($self,"Archive.tgz");
		   
		   
                   sleep 10;
                }        
        });
      
     $thr->join;
   
}


package main;

my $var=new get_diff_files_tar;
#$var->daemonize;
$var->connect_clock;