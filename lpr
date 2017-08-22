#!/usr/bin/perl
#
# Copyright (c) 2017 Stefan Möding <stm@kill-9.net>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.
#


use strict;
use warnings;

use Getopt::Std;
use IO::Socket::INET;


#
# Config
#
my $printer = '10.130.94.120';  # Printer IP
my $port    = '9100';           # JetDirect port


#
# Parse options (all optional)
#
# -J job
# -T title
# -P printer
#
my %opts = ();

getopts('J:T:P:', \%opts) or die "lpr: failed to parse arguments";

# Complete network address for IO::Socket::INET
$printer .= ":${port}";


#
# Get data
#
if ($#ARGV >= 0) {
  # Files given on commandline
  foreach my $file (@ARGV) {
    open(FILE, '<', $file) or die "lpr: can't open ${file}";
    my $data = do { local $/; <FILE> };
    close(FILE);

    &spool($printer, $data);
  }
}
else {
  # No files given on commandline, so use STDIN
  my $data = do { local $/; <STDIN> };

  &spool($printer, $data);
}


########################################################################
#
# spool subroutine
#
sub spool {
  my $printer = shift;
  my $data    = shift;
  my $dry_run = 0;
  my $esc     = chr(27);
  my $eot     = chr(4);
  my $pjl     = '@PJL';

  die "lpr: nothing to print\n" unless (length($data) > 0);

  if ($dry_run == 1) {
    open(FD, '>', '/tmp/lpr.out');
    print FD $data;
    close(FD);
    return;
  }

  #
  # Push data to raw printer port
  #

  my $socket = new IO::Socket::INET(PeerAddr => $printer, Proto => 'tcp');

  die "lpr: can't connect to printer: $!" unless $socket;

  if ($data =~ /^%!PS/) {
    # Switch to PostScript
    $socket->send($esc . "%-12345X${pjl} \n");
    $socket->send("${pjl} SET DUPLEX = ON \n");
    $socket->send("${pjl} ENTER LANGUAGE = POSTSCRIPT \n");

    $socket->send($data);

    # ^D indicates end of PostScript
    $socket->send(${eot});

    $socket->send($esc . '%-12345X');
  }
  else {
    # No PostScript, maybe text?
    $data =~ s/\r?\n/\r\n/g;      # Ensure CRLF
    $socket->send($data);
  }

  #
  # Close socket
  #
  shutdown($socket, 1);
  $socket->close();
}

exit 0;

__END__

=pod

=encoding utf-8

=head1 NAME

lpr - print directly to a JetDirect compatible network printer

=cut

=head1 SYNOPSIS

B<lpr>

B<lpr> [foo.ps] [bar.txt] [...]

=head1 DESCRIPTION

The B<lpr> command prints documents on a network printer. It uses a hardcoded
network address and port number to connect directly to the printer. No local
spooler (e.g. lpd or cups) needs to be available.

The B<lpr> commands detects if a document containing PostScript is printed
and will automatically configure the printer to use duplex printing in this
case.

=head1 OPTIONS

=over 8

=item B<-P>I<printer>

The printer name. Accepted for backward compatibility; this option does not
do anything.

=item B<-T>

The title for the print job. Accepted for backward compatibility; this option
does not do anything.

=item B<-J>

The jobname for the print job. Accepted for backward compatibility; this
option does not do anything.

=back

=head1 DIAGNOSTICS

=over 4

=item failed to parse arguments

The command does not understand the options given on the command line.

=item can't open F<file>

The file name given on the command line could not be opened.

=item nothing to print

Nothing was read on standard input so there is nothing to print.

=item can't connect to printer

The connection to the printer has failed. It may be switched off or the
configured IP address and port number do not belong to the correct printer.

=back

=head1 EXAMPLES

    lpr foo.ps
    lpr bar.txt

=head1 BUGS

The printer name and port are hardcoded.

=head1 AUTHOR

Stefan Möding - L<stm@kill-9.net>

=cut
