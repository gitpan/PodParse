#!/usr/bin/perl


package Parse;


require Exporter;

@ISA = qw(Exporter);

@EXPORT = qw( &parse );

#open(F,"<test.pod");#pod/perlfunc.pod");
#open(F,"<pod/perlfunc.pod");
#open(F,"<pod/perlvar.pod");

# C<> = Code
# B<> = Bold
# I<> = Italics
# V<> = Variable
# P<> = Function/Procedure
# S<> = Switch
# F<> = Filename
# M<> = Manpage
# X<> = Index mark
# R<> = Hyperreference to anything
# L<> = Link to anything (old-style reference)
# W<> = Single word (non-breaking spaces)
# Z<> = No-space
# E<> = HTML Escape
# U<> = Unchanged/verbatim
#
# =without auto-indexing
# =with full-item-indexing
# =without man-warnings
# =head?
# =begin
# =end
# =over
# =back
# =item
# =cut
# =pod
# =comment
# =index

# First, a couple of utility functions for Parse users

# Q&D array dumper
sub dumpout {
	my($arg)=@_;
	local($_);
	if(ref $arg) {
		"[".join(", ",map(dumpout($_),@{$arg}))."]";
	} else {
		$arg;
	}
}

# Wrap incoming text by turning spaces into newlines.
# DO NOT FEED TABS!
sub wrap ($$) {
	my($text,$width) = @_;
	my($i,$w);
	my($m)=-1;
	for ($i=0;$i<length($text);$i++,$w++) {
		if(substr($text,$i,1) eq " ") {
			$m=$i;
		}
		if($w>=$width and $m>-1) {
			substr($text,$m,1)="\n";
			$w=($i-$m);
		}
	}
	$text;
}

# Given text, does something neat/nasty to it, and returns a possible
# complex set of nested arrays
sub chopup {
	local($_)= @_;
	my($i);
	my(@outer)=();
	my(@inner)=();
	my($part)="";
	
	if( !/(\\(.))|(;)|(\/)/ ) {
		return [$_];
	} else {
		while(1) {
			if( length $1 ) {
				$part .= $` . $2;
				$_ = $';
			} elsif( length $3 ) {
				$part .= $`;
				push(@inner,$part);
				push(@outer,[@inner]);
				@inner = ();
				$part = "";
				$_ = $';
			} elsif( length $4 ) {
				$part .= $`;
				push(@inner, $part);
				$part = "";
				$_ = $';
			}
			if( !/(\\(.))|(;)|(\/)/ ) {
				push(@inner,$part.$_);
				return (@outer,[@inner]);
			}
		}
	}
	
}


# Constructor for Parse objects
sub new {
	my($class) = @_;
	my($hash) = {};
	
	$hash->{"auto-indexing"} = 1;
	$hash->{"auto-referencing"} = 1;
	$hash->{"full-item-indexing"} = 0;
	$hash->{"tab-width"} = 8;
	$hash->{"index-prefix"} = "";
	
	$hash->{filename} = "";
	$hash->{line} = 1;
	$hash->{par} = 1;
	$hash->{pos} = 0;
	$hash->{cutting} = 1;
	$hash->{begun} = [];
	$hash->{within} = 0;
	$hash->{blockcomment} = 0;
	$hash->{withinfile}=0;
	
	bless $hash, $class;
}

# Method to parse a pod file, and either return the results
# as one big array, or invoke a callback every interval
sub parse_from_file_by_name ($$;$) {
	my($self,$filename,$callback) = @_;
	local(*Handle);
	
	local($/) = "\n";
	local($_);
	my(@results);
	
	open(Handle,"<$filename");

	$self->start_file($filename);	
	#$self->{filename} = $filename;

	my($par)="";
	my($p)=0;
	
	while(<Handle>) {
		if(/^\s*$/) {
			$par .= $_;
			$p=1;
			#if( $p) {
			#}
		} else {
			if($p) {
				#print "Par [$par]\n";
				push @results,parse_paragraph($self,$par);
				if($callback) {
					while(@results) {
						&$callback(splice(@results,0,6));
					}
				}
				$par = "";
				$p=0;
			}
			$par .= $_;
			$p=0;
		}
	}
	
	close(Handle);

	push @results,parse_paragraph($self,$par);
	
	push @results, flush($self,$callback);
	if($callback) {
		while(@results) {
			&$callback(splice(@results,0,6));
		}
	}
	
	@results;
}


# Given flowed text, return an ASCII equivalent missing formatting.
sub deformat (@) {
	my($out);
	foreach $i (@_) {
		if(ref $i eq "ARRAY") {
			my(@i) = @{$i};
			shift(@i);
			$out .= deformat(@i);
		} else {
			$out .= $i;
		}
	}
	$out;
}

# Given string, break it into possibly multiple elements, escaping
# html special characters
sub escape ($) {
	my(@out);
	while($_[0] =~ /[<>&]/) {
		push @out, $`;
		push @out, ["E", $ASCII2Escape{$&}];
		$_[0] = $';
	}
	push @out, $_[0] if length($_[0]);
	#print "out = @out\n";
	@out;
}

# Sheer magic.
sub flowed2 ($) {
	local($_) = @_;
	my(@out);
	
	my($nest)=0;
	my($begin,$end)=(0,0);
	my($code);

it:
	while(1) {
	if( /[A-Z]</g) {
		$begin = (pos)-2;
		$nest=1;
		while( /([A-Z]<)|(>)|($)/g ) {
			if(length($2) or !length($1)) {
				$nest--;
				if($nest==0 or !length($2)) {
					my($before) = substr($_,0,$begin);
					my($code) = substr($_,$begin,1);
					my($middle) = substr($_,$begin+2,((pos)-$begin-3));
					my($after) = substr($_,pos);
					
#					push @out, "before",$before,"code",$code,"middle",$middle,"after",$after;
					
					#push @out, $before, [$code, $middle];
					
					
					#### Heuristic:
					
					# If code is surrounded by double-quotes, remove them
					if( $code eq "C" and substr($before,-1,1) eq '"' 
									 and substr($after,0,1) eq '"') {
						$before =~ s/"$//;
						$after =~ s/^"//;
					}
					
					#### End heuristics

					push @out, $before if length($before);
					
					my(@mid);
					if( $code eq "L" ) { # Link
						$middle =~ s/([;])/\\$1/g;
						@mid = [chopup($middle)];
						#if(@mid==1) {
						#	unshift @mid,flowed2($mid[0]->[-1]);
						#}
						#@mid = [@mid];
					}
					elsif( $code eq "X" ) { # Index
						if($middle =~ /^\s*$/) {
							$_=$after;
							redo it;
						}
						@mid = chopup($middle);
						if(@mid==1) {
							push @mid, [map(deformat(flowed2($_)), @{$mid[0]}) ];
							if(length($me->{"index-prefix"})) {
								my(@c) = chopup($me->{"index-prefix"});
								foreach (@c) {
									push @$_, @{$mid[-1]};
								}
								push @mid,@c;
							}
						}
						$mid[0] = [flowed2($mid[0]->[-1])];
					}
					elsif( $code eq "R" ) { # Reference
						@mid = chopup($middle);
						if(@mid==1) {
							push @mid, [map(deformat(flowed2($_)), @{$mid[0]}) ];
						}
						$mid[0] = [flowed2($mid[0]->[-1])];
					}
					elsif( $code eq "U" ) { # Unchanged
						@mid = ($middle);
					} else {
						@mid = flowed2($middle);
					}

					push @out, [$code, @mid];
					$_ = $after;
					
					redo it;
				}
			} else {
				$nest++;
			}
		}
	}
		last;
	}
	push @out, $_ if length($_);
	@out;
}

# Prep and entry function for flowed2 
sub flowed ($$) {
	local($me,$_) = @_;
	
	# Canon. whitespace
	s/[\r\n\t ]+/ /gs;
	s/^\s+//;
	s/\s+$//;
	
	[flowed2($_)];
	
}

# Pre-file parse
sub start_file ($$) {
	my($self,$filename) = @_;
	$self->{filename} = $filename;
	$self->{par} = 1;
	$self->{line} = 1;
	$self->{pos} = 0;
	$self->{begun} = [];
	$self->{blockcomment} = 0;
	$self->{withinfile} = 0;
}

#sub escape {
#	if( $_[0] eq "<") {
#		return "lt";
#	} elsif($_[0] eq ">") {
#		return "gt";
#	}
#}

# More magic.
sub flow_heuristics ($) {
	my($arg) = @_;
	
	## Abort heuristics if any explicit references are found
	#return $arg if $arg =~ /R</;
	
	# Turn "func()" into reference to function
	#old style
	$arg =~ s/\b(([\w:]+)\(\))/I<R<$1>>/g;
	#new style
	#$arg =~ s/\b(([\w:]+)\(\))/P<$1>/g;
	
	# Turn "name(3p)" into reference to manpage
	#old style
	$arg =~ s/(^|\s)(([\w:]+)\([0-9a-z]{1,2}\))/$1I<R<$2>>/g;
	#new style
	#$arg =~ s/\b(([\w:]+)\(([1-9a-z]{1,2})\))/M<$1>/g;
	
	#$arg =~ s/C<([\$\@\%][\w:]+)>/V<$1>/g;


	# Turn $a into reference to variable
	#old style
	$arg =~ s/(\s+)([\$\@\%][\w:]+)/${1}C<R<$2>>/g;
	#new style
	#$arg =~ s/(\s+)([\$\@\%]\S[\w:]*)/${1}V<$2>/g;

# C<> = Code
# B<> = Bold
# I<> = Italics
# V<> = Variable
# P<> = Function/Procedure
# S<> = Switch
# F<> = Filename
# M<> = Manpage
# X<> = Index mark
# R<> = Hyperreference to anything
# L<> = Link to anything (old-style reference)
# W<> = Single word (non-breaking spaces)
# Z<> = No-space
# E<> = HTML Escape
# U<> = Unchanged/verbatim

	# Turn B<-e> into S<-e>
	$arg =~ s/B<-([A-Za-z])>/S<-$1>/g;

	# Turn V<var> into reference to variable
	$arg =~ s!V<([\@\$\%][\w:]+)>!V<R<$1;variables/$1;$1>>!g;

	# Turn P<proc> into reference to procedure/function
	$arg =~ s!P<(([\w:]+)(\(\))?)>!P<R<$1;functions/$2;$2>>!g;

	# Turn S<swich> into reference to switch
	$arg =~ s!S<(\-?[\w:]+)>!S<R<$1;switches/$1;$1>>!g;

	# Turn F<filename> into reference to file
	$arg =~ s!F<([\w:\/]+)>!F<R<$1;filenames/$1;$1>>!g;

	# Turn M<man(1)> into reference to manpage
	$arg =~ s!M<(([\w:]+)\(([1-9a-z]{1,2})\))>!M<R<$1;manpages/$3/$2;manpages/$2;$2>>!g;
	
	$arg;
}

sub head_heuristics ($$$) {
	my($self,$arg,$lev)=@_;

#	print "Head: _ = `$arg'\n";

	if( $lev == 1 ) {
		if( $arg eq "NAME" ) {
			$arg = "X<NAME;manpages/".$self->{podname}.";".$self->{podname}.">";
		}
	} elsif( $lev == 2 ) {
		#$arg =~ s/^\s+//;
		#$arg =~ s/\s+$//;
		$arg = "X<$arg>";
	}
	return flow_heuristics($arg);
}

# The interesting bits.
sub parse_paragraph ($$;$) {
	my($self,$paragraph,$dump) = @_;
	
	local(@results);
	sub no_dump { push(@results,@_); }
	$dump ||= \&no_dump;
	
	local($_) = $paragraph;
	
	my($par,$line,$pos) = ($self->{par}, $self->{line}, $self->{pos});
	
	($self->{par}) ++;
	($self->{line}) += tr/\n/\n/;
	($self->{pos}) += length($_);

	if( $self->{blockcomment} and !/^=end\s+comment/) {
		$self->{cmt} .= $_;
		return ();
	}
	
	if($self->{cutting}) {
		if( /^=/ )  {
			if(! /^=cut/) {
				$self->{cutting} = 0;
			}
			return if /^=(resume|pod)/;
		} else {
			return;
		}
	}
	
	if( !$self->{within} and !/^=begin\s+(module|pod)/ ) {
		###push @results, ($par,$line,$pos,"warn","Use =begin pod");
		$self->{podname} = $self->{instname} = $self->{filename};
		
		$self->{podname} =~ s!^.*/!!g;
		$self->{podname} =~ s!\.pod$!!g;
		
		if(!$self->{withinfile}) {
			push @results, ($par,$line,$pos,"begin","file",$self->{filename});
			$self->{withinfile}=1;
		}
		
		push @results, ($par,$line,$pos,"begin","pod",[$self->{podname},$self->{filename},$self->{instname}]);
		$self->{within} = 1;
	}
	
	if( $self->{listpending} and ! /^=item/) {
				$self->{listpending}--;
				$self->{listtype} = 0;
				my(@t) = @{$self->{listenv}};
				@{$t[2]}[5] = 0;
				push @results, @{$t[2]};
				push @results, ($par,$line,$pos,"warn","Item must follow beginning of list",$self->{filename});
	}
	
	if( /^=/) {
		if(/^=cut/) {
			$self->{cutting} = 1;
			return;
		}
		# else {
		#	$self->{cutting} = 0;
		#}
		
		#return if /^=(resume|pod)/;
		
		my($cmd,$rest) = (/^=(\S+)\s*(.*)$/s);
		
		#s/^=((sub)*)head(ing)?(\s|$)/ "=head" . ((length($1)/3)+1) . $4 /ge;
		$cmd =~ s!^((sub)*)head(ing)?$!"head".((length($1)/3)+1)!e;
		if( $cmd eq "over" ) {
			$cmd = "begin";
			$rest = "list $rest";
		} elsif( $cmd eq "back") {
			$cmd = "end";
			$rest = "list $rest";
		}
		
		if( $cmd =~ /^head(\d+)$/) {
			my($lev) = $1;
		
			$rest =~ s/\s+/ /g;
			$rest =~ s/^\s+//;
			$rest =~ s/\s+$//;
			
			if($self->{"auto-referencing"}) {
				$rest = head_heuristics($self,$rest,$lev);
			}

			push @results, ($par,$line,$pos,"head",$lev, flowed($self,$rest) );
		} 
		
		
		elsif( $cmd eq "item" ) {
			unless($self->{list}) {
				push @results, ($par,$line,$pos,"warn","Item outside of list",$self->{filename});
				push @results, ($par,$line,$pos,"begin","list",0);
				$self->{list}++;
				$self->{listpending}++;
			}
			
			@t = @{$self->{listenv}};
			#print "t=",join("|",@t),"\n";
			if(!$t[0]) {
				#print "Item = `$rest'\n";
				if( $rest =~ s/^\*\s*// ) {
					$t[0]="bullet";
				} elsif( $rest =~ s/^(\d+)\.\s*// ) {
					$t[0]="number";
					$t[1]=$1;
					if( $1 != 1) {
						push @results, ($par,$line,$pos,"warn","List should being with 1",$self->{filename});
					}
				} else {
					$t[0]="other";
				}
			} elsif($t[0] eq "bullet") {
				unless($rest =~ s/^\*\s*// ) {
					push @results, ($par,$line,$pos,"warn","Item expected to be `*'",$self->{filename});
				}
			} elsif($t[0] eq "number") {
				if($rest =~ s/^(\d+\.)\s*// ) {
					if($1 != ++$t[1]) {
						push @results, ($par,$line,$pos,"warn","Item expected to be `$t[1].'",$self->{filename});
						$t[1] = $1;
					}
				} else {
						push @results, ($par,$line,$pos,"warn","Item expected to be `$t[1].'",$self->{filename});
				}
			}
			@{$self->{listenv}} = @t;
			
			if($self->{listpending}) {
				$self->{listpending}--;
				$self->{listtype} = $t[0];
				@{$t[2]}[5] = $t[0];
				push @results, @{$t[2]};
			}
			
			if($self->{"auto-indexing"} and $rest !~ /X</ ) {
				if($self->{"full-item-indexing"}) {
					$rest =~ s/([;\\\/])/\\$1/g;
					$rest = "X<$rest>";
				} else {
					# Current behaviour: grab first whole word outside of brackets
					
					my($i)=0;
					my($nest)=0;
					my($c);
					for($i=0;$i<length($rest);$i++) {
						$c = substr($rest,$i,1);
						if( $c eq "<" and substr($rest,$i-1,1) =~ /[A-Z]/) {
							$nest++;
						} elsif( $c eq ">") {
							$nest--;
						} elsif( $c =~ /\s/ and $nest<=0) {
							last;
						}
					}
					my($b) = substr($rest,0,$i);
					$b =~ s/([;\\\/])/\\$1/g;
					$rest = "X<".$b.">".substr($rest,$i);
				}
			}

			
			push @results, ($par,$line,$pos,"item",[$t[0],$t[1]],flowed($self,$rest));
		}
		
		elsif( $cmd eq "begin" ) {
			my($type,@rest) = split(/\s+/,$rest);
			
			if($type eq "list") {
				#push @results, ($par,$line,$pos,"begin","list",0);
				$self->{list}++;
				$self->{listpending}++;
				unshift @{$self->{listenv}}, (0,0,[($par,$line,$pos,"begin","list",0)]);
			}
			elsif($type eq "module" or $type eq "pod") {
				if($self->{within}) {
					push @results, $self->flush($dump);
				}
				$self->{podname} = $rest[0] || $filename;
				$self->{instname} = $rest[1] || $filename;
				if(!$self->{withinfile}) {
					push @results, ($par,$line,$pos,"begin","file",$self->{filename});
					$self->{withinfile}=1;
				}
				push @results, ($par,$line,$pos,"begin","pod",[$self->{podname},$self->{filename},$self->{instname}]);
				$self->{within}=1;
			}
			elsif($type eq "comment") {
				$self->{blockcomment} = 1;
				$self->{cmt} = "";
			}
			else {
				push @results, ($par,$line,$pos, "begin", $type, join(" ",@rest));
			}
			unshift(@{$self->{begun}},$type);
		}
		
		elsif( $cmd eq "end" ) {
			my($type,@rest) = split(/\s+/,$rest);
			
			if($self->{begun}->[-1] ne "$type") {
				# Unmatched end
				push @results, ($par,$line,$pos, "warn","end `$type' without matching begin",$self->{filename});
				# dispose of both end and begin;
				# TODO: make this respect lists
				shift(@{$self->{begun}});
			} 
			
			elsif($type eq "list") {
				#push @results, ($par,$line,$pos,"begin","list",0);
				push @results, ($par,$line,$pos, "end","list",$self->{listenv}->[2]->[5]);
				$self->{list}--;
				shift(@{$self->{listenv}});
				shift(@{$self->{listenv}});
				shift(@{$self->{listenv}});
			}
			elsif($type eq "module" or $type eq "pod") {
				push @results, $self->flush($dump);

				$self->{within}=0;
				# An =end pod should imply cutting, but the 
				# perl parser wouldn't understand that
				###$self->{cutting}=1;
			}
			elsif($type eq "comment") {
				$self->{blockcomment} = 0;
				push @results, ($par,$line,$pos, "comment", $self->{cmt},"");
			}
			else {
				push @results, ($par,$line,$pos, "end", $type, join(" ",@rest));
			}
			shift(@{$self->{begun}});
		}
		
		elsif( $cmd eq "with") {
			my($arg,$opt);
			($arg,undef,$opt) = ($rest =~ /^(\S+)(\s+of\s+(\S+))?/);
			unless(length($opt)) {
				$opt=1;
			}
			if( defined($self->{$arg}) ) {
				push @results, ($par,$line,$pos,"comment","Setting self{$arg} to $opt\n","");
				#print "Setting self{$arg} to $opt\n";
				$self->{$arg} = $opt;
			} else {
				push @results, ($par,$line,$pos,"set",$arg,$opt);
			}
		}
		
		elsif( $cmd eq "without") {
			my($arg) = ($rest =~ /^(\S+)/ );
			if( defined($self->{$arg}) ) {
				push @results, ($par,$line,$pos,"comment","Setting self{$arg} to \"\"\n","");
				#print "Setting self{$arg} to \"\"\n";
				$self->{$arg} = "";
			} else {
				push @results, ($par,$line,$pos,"set",$arg,0);
			}
		}
		
		elsif( $cmd eq "index") {
			my(@i);
			foreach $i (split(/\s*\r?\n\s*/s,$rest)) {
				$i =~ s/^[\s\r\n]+//;
				$i =~ s/[\s\r\n]+$//;
				next unless length($i);
				push @i, chopup($i);
			}
			push @results, ($par,$line,$pos,"index","",[[X,@i]]);
		}
		
		elsif( $cmd eq "comment") {
			push @results, ($par,$line,$pos,"comment",$rest,"");
		}
		
		else {
			push @results, ($par,$line,$pos,"ucmd",$cmd,$rest);
		}
		

	} else {

		#return if $self->{cutting};
		
		if(/^\s/) {
			my(@l) = split(/\n/,$_);
		
			# detabify
			map(s/\t/" " x ($self->{"tab-width"}-(length($`) % $self->{"tab-width"}))/ge,@l);
		
			$_ = join("\n",@l);

			# Find the mimimum number of consecutive spaces at the beginning of
			# each line
			my($min)=0;
			while(/^( +)/gm) {
				$min = length($1) if length($1) < $min or not $min;
			}
		
			# Trim minimum number of spaces from each line
			# (This has effect of butting the text up against
			# the left margin)
			$min = "^ {$min}";
			s/$min//mg;
		
			push @results, ($par,$line,$pos,"verb",$_,"");
		} else {
		
			s/[\r\n\t ]+/ /gs;
			s/^\s+//;
			s/\s+$//;
			
			if($self->{"auto-referencing"}) {
				$_ = flow_heuristics($_);
			}
			
			push @results, ($par,$line,$pos,"flow","",flowed($self,$_));
			#&$dump($par,$line,$pos,"flow",$_);
		}
		
		#Handle everything else;
	}
	
	#&$dump($par,$line,$pos);
	if($self->{listpending}) {
		push(@{$self->{listenv}->[2]},@results);
		();
	} else {
		@results;	
	}
}	

# Post-file method to finish off anything that got started
# but didn't get closed down.

sub flush ($;$) {
	my($self,$dump) = @_;
	
	local(@results);
	sub no_dump { push(@results,@_); }
	$dump ||= \&no_dump;
	
	local($_) = $paragraph;
	
	my($par,$line,$pos) = ($self->{par}, $self->{line}, $self->{pos});
	
	if(!$self->{within}) {
		# Pod never got started.
		# NOTE: an empty pod will return _only_ an "empty" command, not
		# any "begin file" or "begin pod" pairs.
		push @results, ($par,$line,$pos, "empty",$self->{filename},"");
		return @results;
	}
	
	if($self->{blockcomment}) {
		shift(@{$self->{begun}}); # Get rid of comment environment
		push @results, ($par,$line,$pos, "comment",$self->{cmt},"");
	}
	
	foreach $e (@{$self->{begun}}) {
		if( $e eq "list") {
			if( $self->{listpending} ) {
				$self->{listpending}--;
				my(@t) = @{$self->{listenv}};
				@{$t[2]}[5] = 0;
				push @results, @{$t[2]};
			}
			push @results, ($par,$line,$pos, "end","list",0);
			push @results, ($par,$line,$pos, "warn","Unclosed list",$self->{filename});
			pop(@{$self->{listenv}});
			pop(@{$self->{listenv}});
			pop(@{$self->{listenv}});
		} else {
			push @results, ($par,$line,$pos, "end",$e,0);
			push @results, ($par,$line,$pos, "warn","Unclosed $e block",$self->{filename});
		}
	}
	
	if( $self->{within} ) {
		push @results, ($par,$line,$pos,"end","pod",[$self->{podname},$self->{filename},$self->{instname}]); 
		$self->{within} = 0;
	}

	if($self->{withinfile}) {
		push @results, ($par,$line,$pos,"end","file",$self->{filename});
	}
	
	@results;	
}	

%ASCII2Escape = (
	"<" => "lt",
	">" => "gt",
	"&" => "amp",
);

%Escape2ASCII = ( 
	"lt" => "<",
	"gt" => ">",
	"amp" => "&",
	"quot" => '"',
);
