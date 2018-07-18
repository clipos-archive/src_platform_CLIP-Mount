# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright © 2008-2018 ANSSI. All Rights Reserved.
package CLIP::Mount;

use 5.008008;
use strict;
use warnings;
use CLIP::Logger ':all';

require Exporter;

our @ISA = qw(Exporter);

our %EXPORT_TAGS = ( 
'info' => [ qw(
clipmount_rootdev
clipmount_rootdisk
clipmount_encrypted_root
clipmount_bootdev
) ],
'cmd' => [ qw(
clipmount_mount
clipmount_umount
clipmount_mount_all
clipmount_umount_all
) ],
'all' => [ qw(
clipmount_rootdev
clipmount_rootdisk
clipmount_encrypted_root
clipmount_bootdev
clipmount_mount
clipmount_umount
clipmount_mount_all
clipmount_umount_all
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
	
);

our $VERSION = '1.01';

=head1 NAME

CLIP::Mount - Perl extension for managing VFS mounts in CLIP

=head1 VERSION

Version 1.01

=head1 SYNOPSIS

  use CLIP::Mount qw(:info :cmd);

=head1 DESCRIPTION

CLIP::Mount provides an interface for other CLIP modules to access VFS mounts, 
both to get information about current mounts and to perform actual mount operations.
It makes use of CLIP::Logger for logging.

=head2 EXPORT

No functions are exported by default. The following tags can be exported :

=over 4

=item *

C<:info> exports the information reading functions, i.e.

=over 8

=item B<clipmount_rootdev()> 

=item B<clipmount_rootdisk()>

=item B<clipmount_encrypted_root()>

=item B<clipmount_bootdev()> 

=back

=item *

C<:cmd> exports the action functions, i.e.

=over 8

=item B<clipmount_mount()> 

=item B<clipmount_umount()> 

=item B<clipmount_mount_all()> 

=item B<clipmount_umount_all()>

=back

=item *

C<:all> exports all functions from both C<:info> and C<:cmd>.

=back

=head1 FUNCTIONS

CLIP::Mount defines the following functions: 

=cut

###############################################################
#                          SUBS                               #
###############################################################

		       
                       ####################################
		       #      Information functions       #
		       ####################################

=head2 Information functions

=over 4

=item B<clipmount_rootdev()>

Returns the current root device, e.g. "/dev/sda5", or I<undef> in
case of error.

=cut

sub clipmount_rootdev() {
	if (not open IN, "<", "/proc/cmdline") {
		clip_warn "could not open /proc/cmdline";
		return undef;
	}
	my $cmdline =  <IN>;
	close IN;

	if ($cmdline =~ /(?:\S+\s+)*root=(\S+)/) {
		return $1;
	} else {
		clip_warn "could not extract root device from $cmdline";
		return undef;
	}
}

=item B<clipmount_rootdisk()>

Returns the current root disk (of which the root device is a partition, e.g. 
"/dev/sda"), or I<undef> in case of error.

=cut

sub clipmount_rootdisk() {
	my $root;

	if (not defined($root = clipmount_rootdev())) {
		return undef;
	}

	$root =~ s/\d+$//;
	return $root;
}

=item B<clipmount_encrypted_root()>

Returns 1 if the root disk is encrypted, 0 otherwise.

=cut

sub clipmount_encrypted_root(){
	if (not open IN, "<", "/proc/cmdline") {
		clip_warn "could not open /proc/cmdline";
		return undef;
	}
	my $cmdline =  <IN>;
	close IN;

	if ($cmdline =~ /crypt/) {
		return 1;
	} else {
		return 0;
	}
}

=item B<clipmount_bootdev()>

Returns the boot device, e.g. "/dev/sda1", or I<undef> in
case of error.

=cut

sub clipmount_bootdev() {
	if (not open IN, "<", "/proc/cmdline") {
		clip_warn "could not open /proc/cmdline";
		return undef;
	}
	my $cmdline =  <IN>;
	close IN;

	if ($cmdline =~ /(?:\S+\s+)*boot=(\S+)/) {
		return $1;
	} elsif ($cmdline =~ /(?:\S+\s+)*root=(\S+)/) {
		my $boot = $1;
		$boot =~ s/\d+$/1/;
		return $boot;
	} else {
		clip_warn "could not extract boot device from $cmdline";
		return undef;
	}
}



                       ###############################
		       #      Action functions       #
		       ###############################

=back

=head2 Action functions

=over 4

=item B<clipmount_mount($src, $dest, $type, $opts)>

Mounts $src on $dest, with type $type and options $opts.

=over 8

=item - 

$src must be either a full device or directory path, or a symbolic name (without leading '/').

=item - 

$dest must be a full directory path. It will be created automatically if it does not exist
yet, as a directory if $src is either symbolic or a directory or a block device, and as a
regular (empty) file otherwise.

=item - 

$type must be a valid filesystem type, from C</proc/filesystems>.

=item - 

$opts must a comma-separated list of valid mount(8) options.

=back 

The function returns 1 on success, and 0 on failure.

=cut

sub clipmount_mount($$$$) {
	my ($src, $dest, $type, $opts) = @_;

	my $args = "";

	$args .= "-t $type " if (defined($type));
	$args .= "-o \"$opts\" " if (defined($opts));

	$args .= "\"$src\" \"$dest\"";

	if ($src =~ /^\//) {
		if ((-d $src or -b $src) and not -d $dest) {
			clip_warn "creating $dest";
			if (-e $dest and not unlink $dest) {
				clip_warn "failed to remove $dest";
				return 0;
			}
			if (not mkdir $dest) {
				clip_warn "failed to create $dest";
				return 0;
			}
		} elsif (-e $src and not -e $dest) {
			clip_warn "creating $dest";
			if (not open OUT, ">", $dest) {
				clip_warn "failed to create $dest";
				return 0;
			}
			close OUT;
		}
	} else {
		if (not -e $dest and not mkdir $dest) {
			clip_warn "failed to create $dest";
			return 0;
		}
	}

	open PIPE, "mount $args 2>&1 |";
	my @output = <PIPE>;
	close PIPE;
	if ($?) {
		clip_warn "mount of $src to $dest failed";
		foreach (@output) {
			clip_warn "mount output: $_";
		}
		return 0;
	}

	return 1;
}

=item B<clipmount_umount($dest)>

Umounts the VFS mount currently mounted on path $dest. Returns 1 on success, 0 on failure.

=cut

sub clipmount_umount($) {
	my $dest = shift;

	open PIPE, "umount $dest 2>&1 |";
	my @output = <PIPE>;
	close PIPE;
	if ($?) {
		clip_warn "umount of $dest failed";
		foreach (@output) {
			clip_warn "umount output: $_";
		}
		return 0;
	}
	return 1;
}

=item B<clipmount_umount_all($list)>

Unmounts all mounts in the list referenced by $list, in reverse order, and trying to go 
on even in case of errors. Returns 1 if all mounts where unmounted, 0 otherwise.

=cut

sub clipmount_umount_all($) {
	my $lref = shift;
	my @rev = reverse @{$lref};

	my $ret = 1;
	foreach (@rev) {
		clipmount_umount($_) or $ret = 0;
	}

	return $ret;
}

=item B<clipmount_mount_all($list)>

Takes as input a reference $list to a list of references to B<clipmount_mount()> 
argument tuples and tries to mount them in order. Any error encountered along the way
is dealt with by unmounting all mounts mounted up to that point. Returns 1 on success,
and 0 on failure.

$list can be defined in the following way for example:

	$list = [
		[ $src1, $dest1, $type1, $opts1 ],
		...
		[ $srcN, $destN, $typeN, $optsN ]
	];

=cut

sub clipmount_mount_all($) {
	my $list = shift;
	my @mounted = ();

	foreach my $argv (@{$list}) {
		my ($src, $dest, $type, $opts) = @{$argv};

		goto ERR if not clipmount_mount($src, $dest, $type, $opts);
		push @mounted, ($dest);
	}
	return 1;
ERR:
	clipmount_umount_all(\@mounted);
	return 0;
}


1;
__END__

=head1 SEE ALSO

CLIP::Logger(3)

=head1 AUTHOR

Vincent Strubel, E<lt>clip@ssi.gouv.frE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2008 SGDN/DCSSI
Copyright (C) 2011 SGDSN/ANSSI

All rights reserved.

=cut
