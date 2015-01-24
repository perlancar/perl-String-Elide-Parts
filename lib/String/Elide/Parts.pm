package String::Elide::Parts;

# DATE
# VERSION

use 5.010001;
use strict;
use warnings;

use Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw(elide);

sub _elide_part {
    my ($str, $len, $marker, $truncate) = @_;

    my $len_marker = length($marker);
    if ($len <= $len_marker) {
        return substr($marker, 0, $len);
    }

    if ($truncate eq 'left') {
        return $marker . substr($str, length($str) - $len+$len_marker);
    } elsif ($truncate eq 'middle') {
        my $left  = substr($str, 0,
                           ($len-$len_marker)/2);
        my $right = substr($str,
                           length($str) - ($len-$len_marker-length($left)));
        return $left . $marker . $right;
    } elsif ($truncate eq 'ends') {
        if ($len <= 2*$len_marker) {
            return substr($marker . $marker, 0, $len);
        }
        return $marker . substr($str, (length($str)-$len)/2 + $len_marker,
                                $len-2*$len_marker) . $marker;
    } else { # right
        return substr($str, 0, $len-$len_marker) . $marker;
    }
}

sub elide {
    my ($str, $len, $opts) = @_;

    $opts //= {};
    my $truncate  = $opts->{truncate} // 'right';
    my $marker = $opts->{marker} // '..';

    # split into parts by priority
    my @parts;
    my @parts_attrs;
    my $parts_len = 0;
    while ($str =~ m#<elspan([^>]*)>(.*?)</elspan>|(.*?)(?=<elspan)|(.*)#g) {
        if (defined $1) {
            next unless length $2;
            push @parts, $2;
            push @parts_attrs, $1;
        } elsif (defined $3) {
            next unless length $3;
            push @parts, $3;
            push @parts_attrs, undef;
        } elsif (defined $4) {
            next unless length $4;
            push @parts, $4;
            push @parts_attrs, undef;
        }
    }
    return "" unless @parts && $len > 0;
    for my $i (0..@parts-1) {
        $parts_len += length($parts[$i]);
        if (defined $parts_attrs[$i]) {
            my $attrs = {};
            $attrs->{truncate} = $1 // $2
                if $parts_attrs[$i] =~ /\btruncate=(?:"([^"]*)"|(\S+))/;
            $attrs->{prio} = $1 // $2
                if $parts_attrs[$i] =~ /\bprio(?:rity)?=(?:"([^"]*)"|(\S+))/;
            $parts_attrs[$i] = $attrs;
        } else {
            $parts_attrs[$i] = {prio=>1};
        }
    }

    #use DD; dd \@parts; dd \@parts_attrs;

    # used to flip and flop between eliding left and right end, used when
    # truncate is 'ends'
    my $flip = 0;

    # elide and truncate part by part until str is short enough
  PART:
    while (1) {
        if ($parts_len <= $len) {
            return join("", @parts);
        }

        # collect part indexes that have the largest priority
        my @indexes;
        my $highest_prio;
        for (@parts_attrs) {
            $highest_prio = $_->{prio} if !defined($highest_prio) ||
                $highest_prio < $_->{prio};
        }
        for my $i (0..@parts_attrs-1) {
            push @indexes, $i if $parts_attrs[$i]{prio} == $highest_prio;
        }

        # pick which part (index) to elide
        my $index;
        if ($truncate eq 'left') {
            $index = $indexes[0];
        } elsif ($truncate eq 'middle') {
            $index = $indexes[@indexes/2];
        } elsif ($truncate eq 'ends') {
            $index = $flip++ % 2 ? $indexes[0] : $indexes[-1];
        } else { # right
            $index = $indexes[-1];
        }

        my $part_len = length($parts[$index]);
        if ($parts_len - $part_len >= $len) {
            # we need to fully eliminate this part then search for another part
            #say "D:eliminating part (prio=$highest_prio): <$parts[$index]>";
            $parts_len -= $part_len;
            splice @parts, $index, 1;
            splice @parts_attrs, $index, 1;
            next PART;
        }

        # we just need to elide this part and return the result
        #say "D:eliding part (prio=$highest_prio): <$parts[$index]>";
        $parts[$index] = _elide_part(
            $parts[$index],
            $part_len - ($parts_len-$len),
            $marker,
            $parts_attrs[$index]{truncate} // $truncate,
        );
        return join("", @parts);

    } # while 1
}

1;
# ABSTRACT: Elide a string with multiple parts of different priorities

=head1 SYNOPSIS

 use String::Elide qw(elide);

 # single string with no parts

 my $text = "this is your brain";
 elide($text, 16);                       # -> "this is your ..."
 elide($text, 16, {truncate=>"left"});   # -> "...is your brain"
 elide($text, 16, {truncate=>"middle"}); # -> "this is... brain"
 elide($text, 16, {truncate=>"ends"});   # -> "... is your b..."

 elide($text, 16, {marker=>"--"});       # -> "this is your b--"

 # multipart strings: we want to elide URL first, then the Downloading text,
 # then the speed

 $text = "<elspan prio=2>Downloading</elspan> <elspan prio=3 truncate=middle>http://www.example.com/somefile</elspan> 320.0k/5.5M";
 elide($text, 56); # -> "Downloading http://www.example.com/somefile 320.0k/5.5M"
 elide($text, 55); # -> "Downloading http://www.example.com/somefile 320.0k/5.5M"
 elide($text, 50); # -> "Downloading http://www.e..com/somefile 320.0k/5.5M"
 elide($text, 45); # -> "Downloading http://ww..m/somefile 320.0k/5.5M"
 elide($text, 40); # -> "Downloading http://..omefile 320.0k/5.5M"
 elide($text, 35); # -> "Downloading http..efile 320.0k/5.5M"
 elide($text, 30); # -> "Downloading ht..le 320.0k/5.5M"
 elide($text, 25); # -> "Downloading . 320.0k/5.5M"
 elide($text, 24); # -> "Downloading  320.0k/5.5M"
 elide($text, 23); # -> "Download..  320.0k/5.5M"
 elide($text, 20); # -> "Downl..  320.0k/5.5M"
 elide($text, 15); # -> "..  320.0k/5.5M"
 elide($text, 13); # -> "  320.0k/5.5M"
 elide($text, 12); # -> "  320.0k/5.."


=head1 DESCRIPTION

String::Elide is similar to other string eliding modules, with one main
difference: it accepts string marked with parts of different priorities. The
goal is to retain more important information as much as possible when length is
reduced.


=head1 FUNCTIONS

=head2 elide($str, $len[, \%opts]) => str

Elide a string if length exceeds C<$len>.

String can be marked with C<< <elspan prio=N truncate=T>...</elspan> >> so there
can be multiple parts with different priorities and truncate direction. The
default priority is 1. You can mark less important strings with higher priority
to let it be elided first.

Known options:

=over

=item * marker => str (default: '..')

=item * truncate => 'left'|'middle'|'middle'|'ends' (default: 'right')

=back


=head1 SEE ALSO

=head2 Similar elide modules

L<Text::Elide> is simple, does not have many options, and elides at word
boundaries.

L<String::Truncate> has similar interface like String::Elide::Parts and has some
options.

=cut
