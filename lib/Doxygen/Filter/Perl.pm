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
# @copy 2011, Bret Jordan (&lt;jordan2175@gmail.com&gt;, &lt;jordan@open1x.org&gt;)
# $Id: Perl.pm 33 2011-10-26 04:54:17Z jordan2175 $
#*
package Doxygen::Filter::Perl;

use 5.8.8;
use strict;
use warnings;

our $VERSION     = '0.99_02';
$VERSION = eval $VERSION;


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

The Doxygen @fn structural indicator is used to document subroutines/functions/
methods and the parsing engine figures out what is what. In Perl that is a lot
harder to do so I have added a @method and @function structural indicator so 
that they can be documented seperatly. 

NOTE: All doxygen style options and section indicators are supported inside the
structural indicators that we currently support. See the README file.

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

=head1 Data Structure

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

=cut



# Define State Engine
use constant {
    NORMAL              => 0,
    COMMENT             => 1,
    DOXYGEN             => 2,
    POD                 => 3,
    METHOD              => 4,
    DOXYFILE            => 21,
    DOXYCLASS           => 22,
    DOXYFUNCTION        => 23,
    DOXYMETHOD          => 24,
    DOXYCOMMENT         => 25,
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
    $self->{'_iOpenBrace'}      = 0;
    $self->{'_iCloseBrace'}     = 0;
    $self->{'_sCurrentMethodName'}  = undef;
    $self->{'_sCurrentMethodType'}  = undef;
    $self->{'_sCurrentMethodState'} = undef;
}

sub RESETDOXY
{
    my $self = shift;
    $self->{'_aDoxygenBlock'}       = [];
}


sub _init
{
    my $self = shift;

    $self->{'_iState'}          = NORMAL;
    $self->{'_iPreviousState'}  = NORMAL;
    $self->{'_aRawFileData'}    = {};
    $self->{'_hData'}           = {};
    $self->{'_sCurrentClass'}   = undef;    # This will get set i nthe _ProcessPackages line below
    $self->RESETSUB();
    $self->RESETDOXY();
    #$self->_ProcessClasses('main');        # Need to add the main package to the object and data structure, so lets do it here
}




# ----------------------------------------
# Public Methods
# ----------------------------------------
sub ReadFile 
{
    my $self = shift;
    my $sFilename = shift;
    # Lets record the file name in the data structure
    $self->{'_hData'}->{'filename'}->{'fullpath'} = $sFilename;
    $sFilename =~ /^.*\/(.*)$/;
    $self->{'_hData'}->{'filename'}->{'shortname'} = $1;
    open(DATAIN, $sFilename);
    my @aFileData = <DATAIN>;
    close (DATAIN);
    $self->{'_aRawFileData'} = \@aFileData;
}

sub ProcessFile
{
    # This method is a state machine that will search down each line of code to see what it should do
    my $self = shift;
    
    foreach my $line (@{$self->{'_aRawFileData'}})
    {
        # Convert syntax block header to supported doxygen form, if this line is a header
        $line = ${$self->_ConvertToOfficalDoxygenSyntax(\$line)};
            
        # Lets first figure out what state we SHOULD be in and then we will deal with 
        # processing that state. This first block should walk through all the possible
        # transition states, aka, the states you can get to from the state you are in.
        if ($self->{'_iState'} eq NORMAL)
        {
            if    ($line =~ /^\s*sub\s*(.*)/) { $self->_ChangeState(METHOD);  }
            elsif ($line =~ /^\s*#\*\*\s+\@/) { $self->_ChangeState(DOXYGEN); }
            elsif ($line =~ /^=head.*/)       { $self->_ChangeState(POD);     }
        }
        elsif ($self->{'_iState'} eq METHOD)
        {
            if ($line =~ /^\s*#\*\*\s+\@/ ) { $self->_ChangeState(DOXYGEN); } 
        }
        elsif ($self->{'_iState'} eq DOXYGEN)
        {
            # If there are no more comments, then reset the state to the previous state
            unless ($line =~ /^\s*#/) 
            {
                # The general idea is we gather the whole doxygen comment in to an array and process
                # that array all at once in the _ProcessDoxygenCommentBlock.  This way we do not have 
                # to artifically keep track of what type of comment block it is between each line 
                # that we read from the file.
                $self->_ProcessDoxygenCommentBlock(); 
                $self->_RestoreState();
                if ($self->{'_iState'} eq NORMAL)
                {
                    # If this comment block is right next to a subroutine, lets make sure we
                    # handle that condition
                    if    ($line =~ /^\s*sub\s*(.*)/) { $self->_ChangeState(METHOD);  }
                }
            }
        }
        elsif ($self->{'_iState'} eq POD)
        {
            if ($line =~ /^=cut/) { $self->_ChangeState(NORMAL); }
        }


        # Process states
        if ($self->{'_iState'} eq NORMAL)
        {
            if    ($line =~ /^\s*package\s*(.*)\;/)             { $self->_ProcessClasses($line);    }
            elsif ($line =~ /^\s*use\s+[\w:]+/)                 { $self->_ProcessInclude($line);    }
            elsif ($line =~ /^\s*our\s+\$VERSION\s+\=\s+(.*)/)  { $self->_ProcessVersionNumber($1); }
        }        
        elsif ($self->{'_iState'} eq METHOD)  { $self->_ProcessPerlMethod($line); }
        elsif ($self->{'_iState'} eq DOXYGEN) { push (@{$self->{'_aDoxygenBlock'}}, $line); }
    }

    $self->PrintAll();
}

sub PrintAll
{
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
    
    # If nothing is passed in, lets set the current state to the preivous state.
    if (defined $state)
    {
        $self->{_iPreviousState} = $self->{_iState};
        $self->{_iState} = $state;         
    }
    else
    {
        $self->{_iState} = $self->{_iPreviousState};
    }
}

sub _PrintFilenameBlock
{
    my $self = shift;
    print "/** \@file $self->{'_hData'}->{'filename'}->{'fullpath'}\n";
    if (defined $self->{'_hData'}->{'filename'}->{'details'}) { print "$self->{'_hData'}->{'filename'}->{'details'}\n"; }
    print "\@version $self->{'_hData'}->{'filename'}->{'version'}\n";
    print "*/\n";
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

sub _ProcessVersionNumber
{
    # This method will pull the version number out of the code so that it can be used in the file information
    my $self = shift;
    my $version = shift;
    $version =~ s/\'//g;
    $version =~ s/\;//g;
    $self->{'_hData'}->{'filename'}->{'version'} = $version;
}

sub _ProcessClasses
{
    # This method will handle all of the new packages/classes we discover
    # Required:
    #   string  (line of code)
    my $self = shift;
    my $line = shift;
    
    if ($line =~ /^\s*package\s*(.*)\;$/)
    {
        $self->{'_sCurrentClass'} = $1;
        push (@{$self->{'_hData'}->{'class'}->{'classorder'}}, $1);        
    }
}

sub _ProcessInclude
{
    # This method will process all of the includes
    my $self = shift;
    my $line = shift;
    
    $line =~ /^\s*use\s+([\w:]+)/;
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

sub _ProcessPerlMethod
{
    # This method will process the contents of a method
    my $self = shift;
    my $line = shift;
    my $sClassName = $self->{'_sCurrentClass'};

    if ($line =~ /^\s*sub\s*(.*)/) 
    {
        # We should keep track of the order in which the methods were written in the code so we can print 
        # them out in the same order
        push (@{$self->{'_hData'}->{'class'}->{$sClassName}->{'subroutineorder'}}, $1); 
        $self->{'_sCurrentMethodName'} = $1; 
        
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
    $cleanline =~ s/\#.*$//;
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
        $self->_ChangeState(NORMAL);
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
    
sub _ProcessDoxygenCommentBlock
{
    # This method will process an entire comment block in one pass, after it has all been gathered by the state machine
    my $self = shift;
    my @aBlock = @{$self->{'_aDoxygenBlock'}};
    
    # Lets clean up the array in the object now that we have a local copy as we will no longer need that.  We want to make
    # sure it is all clean and ready for the next comment block
    $self->RESETDOXY();

    my $sClassName = $self->{'_sCurrentClass'};
    my $iSubState = 0;
    
    # Remove the command line from the array so we do not re-print it out by mistake
    my $sCommandLine = shift @aBlock;
    
    # Lets look for the end comment block, if their is one, lets remove it
    if ($aBlock[-1] =~ /^\s*#\*\s*$/) { pop @aBlock; }

    $sCommandLine =~ /^\s*#\*\*\s+\@([\w:]+)\s+(.*)/;
    my $sCommand = lc($1);
    my $sOptions = $2; 

    # If the user entered @fn instead of @function, lets change it
    if ($sCommand eq "fn") { $sCommand = "function"; }
    
    # Lets find out what doxygen sub state we should be in
    if    ($sCommand eq 'file')     { $iSubState = DOXYFILE;     }
    elsif ($sCommand eq 'class')    { $iSubState = DOXYCLASS;    }
    elsif ($sCommand eq 'package')  { $iSubState = DOXYCLASS;    }
    elsif ($sCommand eq 'function') { $iSubState = DOXYFUNCTION; }
    elsif ($sCommand eq 'method')   { $iSubState = DOXYMETHOD;   }
    else { $iSubState = DOXYCOMMENT; }


    if ($iSubState eq DOXYFILE ) 
    {
        $self->{'_hData'}->{'filename'}->{'details'} = $self->_RemovePerlCommentFlags(\@aBlock);
    }
    elsif ($iSubState eq DOXYCLASS)
    {
        my $sClassName = $sOptions;
        $self->{'_hData'}->{'class'}->{$sClassName}->{'details'} = $self->_RemovePerlCommentFlags(\@aBlock);
    }
    elsif ($iSubState eq DOXYCOMMENT)
    {
        # For extra comment blocks we need to add the command and option line back to the front of the array
        unshift (@aBlock, "\@$sCommand $sOptions\n");
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
    elsif ($iSubState eq DOXYFUNCTION || $iSubState eq DOXYMETHOD)
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
            if ($aOptions[0] eq "public" || $aOptions[0] eq "private") { $state = shift @aOptions; }
            if (defined $aOptions[0]) { $sMethodName = shift @aOptions;}            
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

        if (defined $sParameters)
        {
            $sParameters = $self->_ConvertParameters($sParameters);
        }
        
        $self->{'_hData'}->{'class'}->{$sClassName}->{'subroutines'}->{$sMethodName}->{'type'} = $sCommand;
        if (defined $state)
        {
            $self->{'_hData'}->{'class'}->{$sClassName}->{'subroutines'}->{$sMethodName}->{'state'} = $state;    
        }
        $self->{'_hData'}->{'class'}->{$sClassName}->{'subroutines'}->{$sMethodName}->{'parameters'} = $sParameters;
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
    
    my $sBlockDetails = "";
    my $iInVerbatimBlock = 0;
    foreach my $line (@$aBlock) 
    {
#        if    ($line =~ /^\s*#\*\*.*$/)   { $line =~ s/^(\s*)#\*\*/$1\/\*\*/; }
#        elsif ($line =~ /^\s*#\*\s*$/)    { $line =~ s/^(\s*)#\*/$1\*\//; }
        
        # Lets check for a verbatim command option
        if    ($line =~ /^\s*#\s*\@(\w+)/) { $line =~ s/^\s*#\s*//; }
                
        if    (defined $1 && $1 eq "verbatim")    { $iInVerbatimBlock = 1; }
        elsif (defined $1 && $1 eq "endverbatim") { $iInVerbatimBlock = 0; }                

        # Lets remove all of the Perl comment markers so long as we are not in a verbatim block
        if ($iInVerbatimBlock == 0) { $line =~ s/^\s*#\s*//; }
        
        $sBlockDetails .= $line;
    }
    return $sBlockDetails;
}

sub _ConvertToOfficalDoxygenSyntax
{
    # This method will check the current line for various unsupported doxygen comment blocks and convert them
    # to the method we support, #** @command.  The reason for this is so that we do not need to add them in 
    # every if statement throughout the code.
    # Required:
    #   string_ref  (line of code)
    # Return:
    #   string_ref  (line of code)
    my $self = shift;
    my $lineref = shift;
    my $line = $$lineref;
    
    # This will match "## @command" and convert it to "#** @command"
    if ($line =~ /^\s*##\s+\@/) { $line =~ s/^(\s*)##(\s+\@)/$1#\*\*$2/; } 
    return \$line;
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



=head1 AUTHOR

Bret Jordan <jordan at open1x littledot org> or <jordan2175 at gmail littledot com>

=head1 LICENSE

Doxygen::Filter::Perl is dual licensed GPLv3 and Commerical. See the LICENSE
file for more details.

=cut

return 1;
