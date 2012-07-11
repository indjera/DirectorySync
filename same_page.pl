#!/usr/bin/perl
use strict;
package  same_page;
use Archive::Tar;
use DBI;
use IO::Socket;
use threads;
use threads::shared;
use File::Copy "cp";
use POSIX 'setsid';

           sub daemonize {                                                                   # стартира приложението в асинхронен режим
            #   chdir '/'               or die "Can't chdir to /: $!";
               open STDIN, '/dev/null'   or die "Can't read /dev/null: $!";
               open STDOUT, '>/dev/null' or die "Can't write to /dev/null: $!";                  
               defined(my $pid = fork)   or die "Can't fork: $!";
               exit if $pid;
               setsid                    or die "Can't start a new session: $!";
               open STDERR, '>&STDOUT'   or die "Can't dup stdout: $!";
           }

$\="\n";
sub new {
    my $ref=shift;
    my $self={};
    bless $self,'same_page' ;
    $self->{interval}="";
    $self->{listDir}="";
    $self->{filelist}=();
    $self->{table}=$ref;
    $self->{dellist}=();
    return $self;
}
sub createTable{
    my $self=shift;
    my $table=$self->{table};
    my $dbh=DBI->connect("DBI:mysql:mydata:127.0.0.1","root","iavelev")or die("error");                # създава таблицата ако не съществува 
     $dbh->do("CREATE TABLE IF NOT EXISTS $table(
              full_name varchar(128) not null ,
              last_change int(10) not null ,
              del bool not null,
              PRIMARY KEY (full_name)
            )"
    );
     
    $dbh->disconnect();

}
sub read_conf {
    my $self=shift;
    my $filename=shift;
    open(FILEH,"<",$filename) or die ("file not exist");                                 # прочита имена на каталози които следим 
    my @filedata=<FILEH>;
    map chomp,@filedata;
    $self->{interval}=shift @filedata;
    $self->{listDir}=\@filedata;
    close FILEH;
}
sub createArchive {
    my $self=shift;
    my $name=shift;
     if (defined @{$self->{filelist}}){
          open (FII,">","filelist");
          $,="\n";
          print FII @{$self->{filelist}} ;
          close FII;
          my $tar=Archive::Tar->new;
          $tar->add_files((@{$self->{filelist}},"filelist"));
          $tar->write($name, COMPRESS_GZIP );
          #$tar->write( 'out.tgz', COMPRESS_GZIP );
          $self->{filelist}=();
    }
    
}
sub scan_list_dir {
    my $self=shift;
    my $table=$self->{table};
    my $dbh=DBI->connect("DBI:mysql:mydata:127.0.0.1","root","iavelev")or die("error $!");   # всички заявки към базата 
    my $sel=$dbh->prepare("SELECT * FROM $table WHERE full_name=? ");
    my $sel1=$dbh->prepare("UPDATE $table SET last_change=?,del=1 WHERE full_name=? ");
    my $sel2=$dbh->prepare("insert into $table values (?,?,?)");
    my $sel3=$dbh->prepare("SELECT * FROM $table  WHERE del=0");
    my $bool= $dbh->selectrow_array("Select COUNT(full_name) from $table");
   # print $bool;
    
    foreach ( @{$self->{listDir} }) {                                                    # списък с каталози които следим 
         my @queue ;
         push @queue ,$_;                                                                     
         while(@queue){                                                                 
         my $tmp=shift @queue;
         opendir(DIRH,$tmp)or die ('error');
             while (my $file=readdir(DIRH)){
                 next if($file eq '.'||$file eq '..');   
                 if(-d "$tmp/$file"){push @queue,"$tmp/$file";}
               #  else {                                                                 # без това не следим за нови каталози 
                     my $time=(stat("$tmp/$file"))[9];
                     $sel->execute( "$tmp/$file" );     
                     if (my @mass_data=$sel->fetchrow_array()){
                         if ($time != $mass_data[1]) {     
                            push  @{$self->{filelist}},"$tmp/$file"; 
                        }
                           $sel1->execute($time,"$tmp/$file");
                        }else{
                            if($bool){
                              push @{$self->{filelist}} ,"$tmp/$file" ;
                              $sel2->execute("$tmp/$file",$time,1);
                            }else {$sel2->execute("$tmp/$file",$time,0);}
                        }   
                  #  }
                }
           close (DIRH);
        }
    }  
    if($bool){
       $sel3->execute();
       my $mass_data=$sel3->fetchall_arrayref();
       if(defined  $mass_data ){
        open(FFF,">","dellist");
       for(@{$mass_data})
       {
        print FFF @{$_}[0];
       }
       push @{$self->{filelist}} ,"dellist" ;
       
       }
       
       $dbh->do("DELETE FROM $table WHERE del=0 ");
       $dbh->do("UPDATE $table SET del=0 WHERE del=1");
    }
    $sel->finish();  
    $sel1->finish();   
    $sel2->finish();
    $sel3->finish(); 
    $dbh->disconnect();
}

sub check_dir_tree{
    my $self=shift;
  
    my $thr=threads->new(
        sub {
            while(1){
            scan_list_dir($self);
           
            
            createArchive($self,"Archive.tgz");
            
            sleep $self->{interval};
         }
        }
    ); 
}

sub send_arch {
    my $socket=IO::Socket::INET->new(
            Proto => 'tcp',
            LocalPort => '6666',
            Listen => 10,
            Reuse => 1
    )or die "IO::Socket::INET->new: $!\n";

    my $client;
    my $file_data;
    while($client=$socket->accept()){
        $client->autoflush(1);
        if(-e "Archive.tgz" && -s "Archive.tgz"){
           print $client 1;
            cp("Archive.tgz", $client);
          # unlink "Archive.tgz";       # може да е в коментар
         }else { print $client 0;}
        close ($client);
        
    }
}
package main;
my $var=new same_page;
#$var->daemonize;
$var->read_conf ('conf_file');
$var->createTable();
$var->check_dir_tree;
$var->send_arch;





