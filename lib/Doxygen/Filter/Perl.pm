#** @file Perl.pm
# @verbatim
#####################################################################
# This program is not guaranteed to work at all, and by using this  #
# program you release the author of any and all liability.          #
#                                                                   #
# You may use this code as long as you are in compliance with the   #
# license (see the LICENSE file) and this notice, disclaimer and    #
# comment box remain intact and unchanged.                          #
#                                                                   #
# Package:     Doxygen::Filter                                      #
# Class:       Perl                                                 #
# Description: Methods for prefiltering Perl code for Doxygen       #
#                                                                   #
# Written by:  Bret Jordan (jordan at open1x littledot org)         #
# Created:     2011-10-13                                           #
##################################################################### 
# @endverbatim
#
# @copy 2011, Bret Jordan (jordan2175@gmail.com, jordan@open1x.org)
# $Id: Perl.pm 58 2011-12-14 06:25:22Z jordan2175 $
#*
package Doxygen::Filter::Perl;

use 5.8.8;
use strict;
use warnings;
use parent qw(Doxygen::Filter);
use Log::Log4perl;
use Pod::POM;
use Doxygen::Filter::Perl::POD;

our $VERSION     = '0.99_21';
$VERSION = eval $VERSION;


# Define State Engine Values
my $hValidStates = {
    'NORMAL'            => 0,
    'COMMENT'           => 1,
    'DOXYGEN'           => 2,
    'POD'               => 3,
    'METHOD'            => 4,
    'DOXYFILE'          => 21,
    'DOXYCLASS'         => 22,
    'DOXYFUNCTION'      => 23,
    'DOXYMETHOD'        => 24,
    'DOXYCOMMENT'       => 25,
};

sub new
{
    my $pkg = shift;
    my $class = ref($pkg) || $pkg;
    
    my $self = {};
    bless ($self, $class);

    # Lets send any passed in arguments to the _init method
    $self->_init(@_);
    return $self;
}

sub DESTROY
{
    my $self = shift;
    $self = {};
}

sub RESETSUB
{
    my $self = shift;
    $self->{'_iOpenBrace'}          = 0;
    $self->{'_iCloseBrace'}         = 0;
    $self->{'_sCurrentMethodName'}  = undef;
    $self->{'_sCurrentMethodType'}  = undef;
    $self->{'_sCurrentMethodState'} = undef;
}

sub RESETFILE  { shift->{'_aRawFileData'}   = [];    }
sub RESETCLASS { shift->{'_sCurrentClass'}  = 'main'; }
sub RESETDOXY  { shift->{'_aDoxygenBlock'}  = [];    }
sub RESETPOD   { shift->{'_aPodBlock'}      = [];    }

sub _init
{
    my $self = shift;
    $self->{'_iDebug'}          = 0;
    $self->{'_sState'}          = undef;
    $self->{'_sPreviousState'}  = [];
    $self->_ChangeState('NORMAL');
    $self->{'_hData'}           = {};
    $self->RESETFILE();
    $self->RESETCLASS();
    $self->RESETSUB();
    $self->RESETDOXY();
    $self->RESETPOD();
}




# ----------------------------------------
# Public Methods
# ----------------------------------------
sub ReadFile 
{
    #** @method public ReadFile ($sFilename)
    # This method will read the contents of the file in to an array
    # and store that in the object as $self->{'_aRawFileData'}
    # @param Required: string (filename)
    #*
    
    my $self = shift;
    my $sFilename = shift;
    # Lets record the file name in the data structure
    $self->{'_hData'}->{'filename'}->{'fullpath'} = $sFilename;

    # Replace forward slash with a black slash
    $sFilename =~ s/\\/\//g;
    # Remove windows style drive letters
    $sFilename =~ s/^.*://;
 
    # Lets grab just the file name not the full path for the short name
    $sFilename =~ /^(.*\/)*(.*)$/;
    $self->{'_hData'}->{'filename'}->{'shortname'} = $2;
 
    open(DATAIN, $sFilename);
    my @aFileData = <DATAIN>;
    close (DATAIN);
    $self->{'_aRawFileData'} = \@aFileData;
}

sub ProcessFile
{
    #** @method public ProcessFile ()
    # This method is a state machine that will search down each line of code to see what it should do
    #*
    my $self = shift;
    my $logger = $self->GetLogger($self);
    $logger->debug("### Entering ProcessFile ###");
    
    foreach my $line (@{$self->{'_aRawFileData'}})
    {
        # Convert syntax block header to supported doxygen form, if this line is a header
        $line = $self->_ConvertToOfficalDoxygenSyntax($line);
            
        # Lets first figure out what state we SHOULD be in and then we will deal with 
        # processing that state. This first block should walk through all the possible
        # transition states, aka, the states you can get to from the state you are in.
        if ($self->{'_sState'} eq 'NORMAL')
        {
            $logger->debug("We are in state: NORMAL");
            if    ($line =~ /^\s*sub\s*(.*)/) { $self->_ChangeState('METHOD');  }
            elsif ($line =~ /^\s*#\*\*\s*\@/) { $self->_ChangeState('DOXYGEN'); }
            elsif ($line =~ /^=.*/)           { $self->_ChangeState('POD');     }
        }
        elsif ($self->{'_sState'} eq 'METHOD')
        {
            $logger->debug("We are in state: METHOD");
            if ($line =~ /^\s*#\*\*\s*\@/ ) { $self->_ChangeState('DOXYGEN'); } 
        }
        elsif ($self->{'_sState'} eq 'DOXYGEN')
        {
            $logger->debug("We are in state: DOXYGEN");
            # If there are no more comments, then reset the state to the previous state
            unless ($line =~ /^\s*#/) 
            {
                # The general idea is we gather the whole doxygen comment in to an array and process
                # that array all at once in the _ProcessDoxygenCommentBlock.  This way we do not have 
                # to artifically keep track of what type of comment block it is between each line 
                # that we read from the file.
                $logger->debug("End of Doxygen Comment Block");
                $self->_ProcessDoxygenCommentBlock(); 
                $self->_RestoreState();
                $logger->debug("We are in state $self->{'_sState'}");
                if ($self->{'_sState'} eq 'NORMAL')
                {
                    # If this comment block is right next to a subroutine, lets make sure we
                    # handle that condition
                    if ($line =~ /^\s*sub\s*(.*)/) { $self->_ChangeState('METHOD');  }
                }
            }
        }
        elsif ($self->{'_sState'} eq 'POD') 
        {
            if ($line =~ /^=cut/) 
            { 
                push (@{$self->{'_aPodBlock'}}, $line);
                $self->_ProcessPodCommentBlock();
                $self->_RestoreState(); 
            }
        }


        # Process states
        if ($self->{'_sState'} eq 'NORMAL')
        {
            if ($line =~ /^\s*package\s*(.*)\;$/) 
            { 
                $self->{'_sCurrentClass'} = $1;
                push (@{$self->{'_hData'}->{'class'}->{'classorder'}}, $1);        
            }
            elsif ($line =~ /our\s+\$VERSION\s*=\s*(.*);$/) 
            {
                # our $VERSION = '0.99_01';
                # use version; our $VERSION = qv('0.3.1'); - Thanks Hoppfrosch for the suggestion
                my $version = $1;
                $version =~ s/[\'\"\(\)\;]//g;
                $version =~ s/qv//;
                $self->{'_hData'}->{'filename'}->{'version'} = $version;
            }
            elsif ($line =~ /^\s*use\s+([\w:]+)/) 
            {
                my $sIncludeModule = $1;
                if (defined($sIncludeModule)) 
                {
                    unless ($sIncludeModule eq "strict" || $sIncludeModule eq "warnings" || $sIncludeModule eq "vars" || $sIncludeModule eq "Exporter" || $sIncludeModule eq "base") 
                    {
                        # Allows doxygen to know where to look for other packages
                        $sIncludeModule =~ s/::/\//g;
                        push (@{$self->{'_hData'}->{'includes'}}, $sIncludeModule);
                    }
                }  
            }
        }        
        elsif ($self->{'_sState'} eq 'METHOD')  { $self->_ProcessPerlMethod($line); }
        elsif ($self->{'_sState'} eq 'DOXYGEN') { push (@{$self->{'_aDoxygenBlock'}}, $line); }
        elsif ($self->{'_sState'} eq 'POD')     { push (@{$self->{'_aPodBlock'}}, $line);}
    }
}

sub PrintAll
{
    #** @method public PrintAll ()
    # This method will print out the entire data structure in a form that Doxygen can work with.
    # It is important to note that you are basically making the output look like C code so that 
    # packages and classes need to have start and end blocks and need to include all of the 
    # elements that are part of that package or class
    #*
    my $self = shift;
    $self->_PrintFilenameBlock();
    $self->_PrintIncludesBlock();
    
    foreach my $class (@{$self->{'_hData'}->{'class'}->{'classorder'}})
    {
        $self->_PrintClassBlock($class);
        
        # Build an object where methods are organizaed by type first, this way they are all grouped correctly
        my $hMethodData = {};
        foreach my $sMethodName (@{$self->{'_hData'}->{'class'}->{$class}->{'subroutineorder'}})
        {
            # $hMethodData->{function/method}->{public/private}->{name} = 1
            my $sType = $self->{'_hData'}->{'class'}->{$class}->{'subroutines'}->{$sMethodName}->{'type'};
            my $sState = $self->{'_hData'}->{'class'}->{$class}->{'subroutines'}->{$sMethodName}->{'state'};
            $hMethodData->{$sType}->{$sState}->{$sMethodName} = 1;
        }

        foreach my $type (keys(%{$hMethodData}))
        {
            my $sTypeName = $type . "s";
            $sTypeName =~ s/([^_]+)/\u\L$1/gi;
            print "/** \@name Avaliable $sTypeName */\n";
            print "/** \@{ */\n";
            foreach my $state (keys(%{$hMethodData->{$type}}))
            {
                foreach my $method (keys(%{$hMethodData->{$type}->{$state}}))
                {
                    $self->_PrintMethodBlock($class,$state,$type,$method);
                }
            }
            # End of named group block
            print "/** \@} */\n";
        }
        # Print end of class mark
        print "}\;\n";
    }
}


# ----------------------------------------
# Private Methods
# ----------------------------------------
sub _RestoreState { shift->_ChangeState(); }
sub _ChangeState
{
    my $self = shift;
    my $state = shift;
    my $logger = $self->GetLogger($self);
    
    if (defined $state && exists $hValidStates->{$state})
    {
        # If there was a value passed in and it is a valid value lets make it active 
        $logger->debug("State passed in: $state");
        unless (defined $self->{'_sState'} && $self->{'_sState'} eq $state)
        {
            # Need to push the current state to the array BEFORE we change it and only
            # if we are not currently at that state
            push (@{$self->{'_sPreviousState'}}, $self->{'_sState'});
            $self->{'_sState'} = $state;
        } 
    }
    else
    {
        # If nothing is passed in, lets set the current state to the preivous state.
        $logger->debug("No state passed in, lets revert to previous state");
        my $previous = pop @{$self->{'_sPreviousState'}};
        $logger->debug("Previous state was $previous");
        unless (defined $previous) 
        { 
            $logger->error("There is no previous state! Setting to NORMAL");
            $previous = 'NORMAL';
        }
        $self->{'_sState'} = $previous;
    }
}

sub _PrintFilenameBlock
{
    my $self = shift;
    if (defined $self->{'_hData'}->{'filename'}->{'fullpath'})
    {
        print "/** \@file $self->{'_hData'}->{'filename'}->{'fullpath'}\n";
        if (defined $self->{'_hData'}->{'filename'}->{'details'}) { print "$self->{'_hData'}->{'filename'}->{'details'}\n"; }
        if (defined $self->{'_hData'}->{'filename'}->{'version'}) { print "\@version $self->{'_hData'}->{'filename'}->{'version'}\n"; }
        print "*/\n";        
    }
}

sub _PrintIncludesBlock
{
    my $self = shift;
    foreach my $include (@{$self->{'_hData'}->{'includes'}})
    {
        print "\#include \"$include.pm\"\n";
    }
    print "\n";
}

sub _PrintClassBlock
{
    my $self = shift;
    my $sFullClass = shift;
    
    $sFullClass =~ /(.*)\:\:(\w+)$/;
    my $parent = $1;
    my $class = $2;
    
    print "/** \@class $sFullClass\n";
    
    my $details = $self->{'_hData'}->{'class'}->{$sFullClass}->{'details'};
    if (defined $details) { print "$details\n"; }

    my $comments = $self->{'_hData'}->{'class'}->{$sFullClass}->{'comments'};
    if (defined $comments) { print "$comments\n"; }   
    
    print "\@nosubgrouping */\n";

    print "class $sFullClass : public $parent { \n";
    print "public:\n";
}

sub _PrintMethodBlock
{
    my $self = shift;
    my $class = shift;
    my $state = shift;
    my $type = shift;
    my $method = shift;
    my $parameters = $self->{'_hData'}->{'class'}->{$class}->{'subroutines'}->{$method}->{'parameters'} || "";

    print "/** \@fn $state $type $method\(\)\n";

    my $details = $self->{'_hData'}->{'class'}->{$class}->{'subroutines'}->{$method}->{'details'};
    if (defined $details) { print "$details\n"; }
    else { print "Undocumented Method\n"; }

    my $comments = $self->{'_hData'}->{'class'}->{$class}->{'subroutines'}->{$method}->{'comments'};
    if (defined $comments) { print "$comments\n"; }

    # Print collapsible source code block   
    print "\@htmlonly\n";
    print "<div id='codesection-$method' class='dynheader closed' style='cursor:pointer;' onclick='return toggleVisibility(this)'>\n";
    print "\t<img id='codesection-$method-trigger' src='closed.png' style='display:inline'><b>Code:</b>\n";
    print "</div>\n";
    print "<div id='codesection-$method-summary' class='dyncontent' style='display:block;font-size:small;'>click to view</div>\n";
    print "<div id='codesection-$method-content' class='dyncontent' style='display: none;'>\n";
    print "\@endhtmlonly\n";
    
    print "\@code\n";
    print "\# Number of lines of code in $method: $self->{'_hData'}->{'class'}->{$class}->{'subroutines'}->{$method}->{'length'}\n";
    print "$self->{'_hData'}->{'class'}->{$class}->{'subroutines'}->{$method}->{'code'}\n";
    print "\@endcode \@htmlonly\n";
    print "</div>\n";
    print "\@endhtmlonly */\n";

    print "$state $type $method\($parameters\)\;\n";      
}

sub _ProcessPerlMethod
{
    # This method will process the contents of a method
    my $self = shift;
    my $line = shift;
    my $sClassName = $self->{'_sCurrentClass'};

    if ($line =~ /^\s*sub\s+(.*)/) 
    {
        # We should keep track of the order in which the methods were written in the code so we can print 
        # them out in the same order
        my $sName = $1;
        # If they have declared the subrountine with a brace on the same line, lets remove it
        $sName =~ s/\{.*\}?//;
        # Remove any leading or trailing whitespace from the name, just to be safe
        $sName =~ s/\s//g;
        
        push (@{$self->{'_hData'}->{'class'}->{$sClassName}->{'subroutineorder'}}, $sName); 
        $self->{'_sCurrentMethodName'} = $sName; 
    }
    my $sMethodName = $self->{'_sCurrentMethodName'};
    
    # Lets find out if this is a public or private method/function based on a naming standard
    if ($sMethodName =~ /^_/) { $self->{'_sCurrentMethodState'} = 'private'; }
    else { $self->{'_sCurrentMethodState'} = 'public'; }
    
    my $sMethodState = $self->{'_sCurrentMethodState'};
    
    # We need to count the number of open and close braces so we can see if we are still in a subroutine or not
    # but we need to becareful so that we do not count braces in comments and braces that are in match patters /\{/
    # If there are more open then closed, then we are still in a subroutine
    my $cleanline = $line;
    # Remove any comments even those inline with code
    $cleanline =~ s/#.*$//;
    # TODO need to find a good way to remove braces from counting when they are in a pattern match but not when they
    # are supposed to be there as in the second use case listed below.  Below the use cases is some ideas on how to do this.
    # use case: $a =~ /\{/
    # use case: if (/\{/) { foo; }
    $cleanline =~ s#/.*/##g;
    
    $self->{'_iOpenBrace'} += @{[$cleanline =~ /\{/g]};
    $self->{'_iCloseBrace'} += @{[$cleanline =~ /\}/g]};        
    
    
    # Use Case 1: sub foo { return; }
    # Use Case 2: sub foo {\n}    
    # Use Case 3: sub foo \n {\n }

    if ($self->{'_iOpenBrace'} > $self->{'_iCloseBrace'}) 
    { 
        # Use Case 2, still in subroutine
    }
    elsif ($self->{'_iOpenBrace'} > 0 && $self->{'_iOpenBrace'} == $self->{'_iCloseBrace'}) 
    { 
        # Use Case 1, we are leaving a subroutine
        $self->_ChangeState('NORMAL');
        $self->RESETSUB();
    }
    else 
    { 
        # Use Case 3, still in subroutine
    }

    # Record the current line for code output
    $self->{'_hData'}->{'class'}->{$sClassName}->{'subroutines'}->{$sMethodName}->{'code'} .= $line;
    $self->{'_hData'}->{'class'}->{$sClassName}->{'subroutines'}->{$sMethodName}->{'length'}++; 
    
    # Only set these values if they were not already set by a comment block outside the subroutine
    # This is for public/private
    unless (defined $self->{'_hData'}->{'class'}->{$sClassName}->{'subroutines'}->{$sMethodName}->{'state'})
    {
        $self->{'_hData'}->{'class'}->{$sClassName}->{'subroutines'}->{$sMethodName}->{'state'} = $sMethodState;
    }
    # This is for function/method
    unless (defined $self->{'_hData'}->{'class'}->{$sClassName}->{'subroutines'}->{$sMethodName}->{'type'}) 
    {
        $self->{'_hData'}->{'class'}->{$sClassName}->{'subroutines'}->{$sMethodName}->{'type'} = "method";
    }
}


sub _ProcessPodCommentBlock
{
    # This method will process an entire POD block in one pass, after it has all been gathered by the state machine.
    my $self = shift;
    
    my $sClassName = $self->{'_sCurrentClass'};    
    my @aBlock = @{$self->{'_aPodBlock'}};
    
    # Lets clean up the array in the object now that we have a local copy as we will no longer need that.  We want to make
    # sure it is all clean and ready for the next comment block
    $self->RESETPOD();

    my $sPodRawText;
    foreach (@aBlock) { $sPodRawText .= $_; }

    my $parser = new Pod::POM();
    my $pom = $parser->parse_text($sPodRawText);
    my $sPodParsedText = Doxygen::Filter::Perl::POD->print($pom);

    $self->{'_hData'}->{'class'}->{$sClassName}->{'comments'} .= $sPodParsedText;
}


sub _ProcessDoxygenCommentBlock
{
    # This method will process an entire comment block in one pass, after it has all been gathered by the state machine
    my $self = shift;
    my $logger = $self->GetLogger($self);
    $logger->debug("### Entering _ProcessDoxygenCommentBlock ###");
    
    my @aBlock = @{$self->{'_aDoxygenBlock'}};
    
    # Lets clean up the array in the object now that we have a local copy as we will no longer need that.  We want to make
    # sure it is all clean and ready for the next comment block
    $self->RESETDOXY();

    my $sClassName = $self->{'_sCurrentClass'};
    my $sSubState = '';
    $logger->debug("We are currently in class $sClassName");
    
    # Remove the command line from the array so we do not re-print it out by mistake
    my $sCommandLine = $aBlock[0];
    $logger->debug("The command line for this doxygen comment is $sCommandLine");

    $sCommandLine =~ /^\s*#\*\*\s+\@([\w:]+)\s+(.*)/;
    my $sCommand = lc($1);
    my $sOptions = $2; 
    $logger->debug("Command: $sCommand");
    $logger->debug("Options: $sOptions");

    # If the user entered @fn instead of @function, lets change it
    if ($sCommand eq "fn") { $sCommand = "function"; }
    
    # Lets find out what doxygen sub state we should be in
    if    ($sCommand eq 'file')     { $sSubState = 'DOXYFILE';     }
    elsif ($sCommand eq 'class')    { $sSubState = 'DOXYCLASS';    }
    elsif ($sCommand eq 'package')  { $sSubState = 'DOXYCLASS';    }
    elsif ($sCommand eq 'function') { $sSubState = 'DOXYFUNCTION'; }
    elsif ($sCommand eq 'method')   { $sSubState = 'DOXYMETHOD';   }
    else { $sSubState = 'DOXYCOMMENT'; }
    $logger->debug("Substate is now $sSubState");

    if ($sSubState eq 'DOXYFILE' ) 
    {
        $logger->debug("Processing a Doxygen file object");
        # We need to remove the command line from this block
        shift @aBlock;
        $self->{'_hData'}->{'filename'}->{'details'} = $self->_RemovePerlCommentFlags(\@aBlock);
    }
    elsif ($sSubState eq 'DOXYCLASS')
    {
        $logger->debug("Processing a Doxygen class object");
        my $sClassName = $sOptions;
        # We need to remove the command line from this block
        shift @aBlock;
        $self->{'_hData'}->{'class'}->{$sClassName}->{'details'} = $self->_RemovePerlCommentFlags(\@aBlock);
    }
    elsif ($sSubState eq 'DOXYCOMMENT')
    {
        $logger->debug("Processing a Doxygen class object");
        # For extra comment blocks we need to add the command and option line back to the front of the array
        my $sMethodName = $self->{'_sCurrentMethodName'};
        if (defined $sMethodName)
        {
            $self->{'_hData'}->{'class'}->{$sClassName}->{'subroutines'}->{$sMethodName}->{'comments'} .= $self->_RemovePerlCommentFlags(\@aBlock);
            $self->{'_hData'}->{'class'}->{$sClassName}->{'subroutines'}->{$sMethodName}->{'comments'} .= "\n";
        }
        else 
        {
            $self->{'_hData'}->{'class'}->{$sClassName}->{'comments'} .= $self->_RemovePerlCommentFlags(\@aBlock);
            $self->{'_hData'}->{'class'}->{$sClassName}->{'comments'} .= "\n";
        }
    }
    elsif ($sSubState eq 'DOXYFUNCTION' || $sSubState eq 'DOXYMETHOD')
    {
        # Process the doxygen header first then loop through the rest of the comments
        $sOptions =~ /^(.*)\s*\(\s*(.*)\s*\)/;
        $sOptions = $1;
        my $sParameters = $2;
    
        my @aOptions;
        my $state;        
        my $sMethodName;
        
        if (defined $sOptions)
        {
            @aOptions = split (" ", $sOptions);
            # State = Public/Private
            if ($aOptions[0] eq "public" || $aOptions[0] eq "private") 
            { 
                $state = shift @aOptions;
                # Remove any leading or training spaces
                $state =~ s/\s//g; 
            }
            if (defined $aOptions[0]) 
            { 
                $sMethodName = shift @aOptions;
                # Remove any leading or training spaces
                $sMethodName =~ s/\s//g; 
            }            
        }       

        unless (defined $sMethodName) 
        {
            # If we are already in a subroutine and a user uses sloppy documentation and only does
            # #**@method in side the subroutine, then lets pull the current method name from the object.
            # If there is no method defined there, we should die.
            if (defined $self->{'_sCurrentMethodName'}) { $sMethodName = $self->{'_sCurrentMethodName'}; } 
            else { die "Missing method name in $sCommand syntax"; } 
        }

        # If we are not yet in a subroutine, lets keep track that we are now processing a subroutine and its name
        unless (defined $self->{'_sCurrentMethodName'}) { $self->{'_sCurrentMethodName'} = $sMethodName; }

        if (defined $sParameters) { $sParameters = $self->_ConvertParameters($sParameters); }
        
        $self->{'_hData'}->{'class'}->{$sClassName}->{'subroutines'}->{$sMethodName}->{'type'} = $sCommand;
        if (defined $state)
        {
            $self->{'_hData'}->{'class'}->{$sClassName}->{'subroutines'}->{$sMethodName}->{'state'} = $state;    
        }
        $self->{'_hData'}->{'class'}->{$sClassName}->{'subroutines'}->{$sMethodName}->{'parameters'} = $sParameters;
        # We need to remove the command line from this block
        shift @aBlock;
        $self->{'_hData'}->{'class'}->{$sClassName}->{'subroutines'}->{$sMethodName}->{'details'} = $self->_RemovePerlCommentFlags(\@aBlock);

    } # End DOXYFUNCTION || DOXYMETHOD
}

sub _RemovePerlCommentFlags
{
    # This method will remove all of the comment marks "#" for our output to Doxygen.  If the line is 
    # flagged for verbatim then lets not do anything.
    # Required:
    #   array_ref   (array of lines of doxygen comments)
    # Return: 
    #   string  (doxygen comments in one long string)
    my $self = shift;
    my $aBlock = shift;
    my $logger = $self->GetLogger($self);
    $logger->debug("### Entering _RemovePerlCommentFlags ###");
    
    my $sBlockDetails = "";
    my $iInVerbatimBlock = 0;
    foreach my $line (@$aBlock) 
    {
        # Lets check for a verbatim command option like '# @verbatim'
        if ($line =~ /^\s*#\s*\@verbatim/) 
        { 
            $logger->debug("Found verbatim command");
            # We need to remove the comment marker from the '# @verbaim' line now since it will not be caught later
            $line =~ s/^\s*#\s*//;
            $iInVerbatimBlock = 1;
        }
        elsif ($line =~ /^\s*#\s*\@endverbatim/)
        { 
            $logger->debug("Found endverbatim command");
            $iInVerbatimBlock = 0;
        }
        # Lets remove any doxygen command initiator
        $line =~ s/^\s*#\*\*\s*//;
        # Lets remove any doxygen command terminators
        $line =~ s/^\s*#\*\s*//;
        # Lets remove all of the Perl comment markers so long as we are not in a verbatim block
        if ($iInVerbatimBlock == 0) { $line =~ s/^\s*#\s*//; }
        $logger->debug("code: $line");
        $sBlockDetails .= $line;
    }
    return $sBlockDetails;
}

sub _ConvertToOfficalDoxygenSyntax
{
    # This method will check the current line for various unsupported doxygen comment blocks and convert them
    # to the type we support, '#** @command'.  The reason for this is so that we do not need to add them in 
    # every if statement throughout the code.
    # Required:
    #   string  (line of code)
    # Return:
    #   string  (line of code)
    my $self = shift;
    my $line = shift;
    
    # This will match "## @command" and convert it to "#** @command"
    if ($line =~ /^\s*##\s+\@/) { $line =~ s/^(\s*)##(\s+\@)/$1#\*\*$2/; } 
    return $line;
}

sub _ConvertParameters
{
    # This method will change the $, @, and %, etc to written names so that Doxygen does not have a problem with them
    my $self = shift;
    my $sParameters = shift;

    # Lets clean up the parameters list so that it will work with Doxygen
    $sParameters =~ s/\$\$/scalar_ref /g;
    $sParameters =~ s/\@\$/array_ref /g;
    $sParameters =~ s/\%\$/hash_ref /g;
    $sParameters =~ s/\$/scalar /g;
    $sParameters =~ s/\@/list /g;
    $sParameters =~ s/\%/hash /g;
    
    return $sParameters;
}

=head1 NAME

Doxygen::Filter::Perl - A perl code pre-filter for Doxygen

=head1 DESCRIPTION

The Doxygen::Filter::Perl module is designed to provide support for documenting
perl scripts and modules to be used with the Doxygen engine.  We plan on 
supporting most Doxygen style comments and POD (plain old documentation) style 
comments. The Doxgyen style comment blocks for methods/functions can be inside 
or outside the method/function.  

=head1 USAGE

Install Doxygen::Filter::Perl via CPAN or from source.  If you install from 
source then do:

    perl Makefile.PL
    make
    make install
    
Make sure that the doxygen-filter-perl script was copied from this project into
your path somewhere and that it has RX permissions. Example:

    /usr/local/bin/doxygen-filter-perl

Copy over the Doxyfile file from this project into the root directory of your
project so that it is at the same level as your lib directory. This file will
have all of the presets needed for documenting Perl code.  You can edit this
file with the doxywizard tool if you so desire or if you need to change the 
lib directory location or the output location (the default output is ./doc).
Please see the Doxygen manual for information on how to configure the Doxyfile
via a text editor or with the doxywizard tool.
Example:

    /home/jordan/workspace/PerlDoxygen/trunk/Doxyfile
    /home/jordan/workspace/PerlDoxygen/trunk/lib/Doxygen/Filter/Perl.pm

Once you have done this you can simply run the following from the root of your
project to document your Perl scripts or methods. Example:

    /home/jordan/workspace/PerlDoxygen/trunk/> doxygen Doxyfile

All of your documentation will be in the ./doc/html/directory inside of your
project root.

=head1 DOXYGEN SUPPORT

The following Doxygen style comment is the preferred block style, though others
are supported and are listed below:

    #** 
    # ........
    #* 

You can also start comment blocks with "##" and end comment blocks with a blank
line or real code, this allows you to place comments right next to the 
subroutines that they refer to if you wish.  A comment block must have 
continuous "#" comment markers as a blank line can be used as a termination
mark for the doxygen comment block.

In other languages the Doxygen @fn structural indicator is used to document 
subroutines/functions/methods and the parsing engine figures out what is what. 
In Perl that is a lot harder to do so I have added a @method and @function 
structural indicator so that they can be documented seperatly. 

=head2 Supported Structural Indicators

    #** @file [filename]
    # ........
    #* 
    
    #** @class [class name (ex. Doxygen::Filter::Perl)]
    # ........
    #* 
    
    #** @method or @function [public|private] [method-name] (parameters)
    # ........
    #* 
    
    #** @section [section-name]
    # ........
    #* 
    
    #** @brief [notes]
    # ........
    #* 

=head2 Support Style Options and Section Indicators
     
All doxygen style options and section indicators are supported inside the
structural indicators that we currently support.

=head2 Documenting Subroutines/Functions/Methods

The Doxygen style comment blocks that describe a function or method can
exist before, after, or inside the subroutine that it is describing. Examples
are listed below. It is also important to note that you can leave the public/private
out and the filter will guess based on the subroutine name. The normal convention 
in other languages like C is to have the function / method start with an "_" if it
is private/protected.  We do the same thing here even though there is really no 
such thing in Perl. The whole reason for this is to help users of the code know 
what functions they should call directly and which they should not.  The generic 
documentation blocks for functions and methods look like:

    #** @function [public|private] function-name (parameters)
    # @brief A brief description of the function
    #
    # A detailed description of the function
    # @params [required|optional] value
    # @returns value
    # ....
    #*

    #** @method [public|private] method-name (parameters)
    # @brief A brief description of the method
    #
    # A detailed description of the method
    # @params [required|optional] value
    # @returns value
    # ....
    #*

The parameters would normally be something like $foo, @bar, or %foobar.  I have
also added support for scalar, array, and hash references and those would be 
documented as $$foo, @$bar, %$foobar.  An example would look this:

    #** @method public ProcessDataValues ($$sFile, %$hDataValues)

=head2 Function / Method Example

    sub test1
    {
        #** @method public test1 ($value)
        # ....
        #*        
    }

    #** @method public test2 ($value)
    # ....
    #*    
    sub test2
    {
  
    }

=head1 DATA STRUCTURE

    $self->{'_hData'}->{'filename'}->{'fullpath'}   = string
    $self->{'_hData'}->{'filename'}->{'shortname'}  = string
    $self->{'_hData'}->{'filename'}->{'version'}    = string
    $self->{'_hData'}->{'filename'}->{'details'}    = string
    $self->{'_hData'}->{'includes'}                 = array

    $self->{'_hData'}->{'class'}->{'classorder'}                = array
    $self->{'_hData'}->{'class'}->{$class}->{'subroutineorder'} = array
    $self->{'_hData'}->{'class'}->{$class}->{'details'}         = string
    $self->{'_hData'}->{'class'}->{$class}->{'comments'}        = string

    $self->{'_hData'}->{'class'}->{$class}->{'subroutines'}->{$method}->{'type'}        = string (method / function)
    $self->{'_hData'}->{'class'}->{$class}->{'subroutines'}->{$method}->{'state'}       = string (public / private)
    $self->{'_hData'}->{'class'}->{$class}->{'subroutines'}->{$method}->{'parameters'}  = string (method / function parameters)
    $self->{'_hData'}->{'class'}->{$class}->{'subroutines'}->{$method}->{'code'}        = string
    $self->{'_hData'}->{'class'}->{$class}->{'subroutines'}->{$method}->{'length'}      = integer
    $self->{'_hData'}->{'class'}->{$class}->{'subroutines'}->{$method}->{'details'}     = string
    $self->{'_hData'}->{'class'}->{$class}->{'subroutines'}->{$method}->{'comments'}    = string

=head1 AUTHOR

Bret Jordan <jordan at open1x littledot org> or <jordan2175 at gmail littledot com>

=head1 LICENSE

Doxygen::Filter::Perl is dual licensed GPLv3 and Commerical. See the LICENSE
file for more details.

=cut

return 1;
