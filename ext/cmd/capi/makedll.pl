#!/usr/bin/perl
# File makedll.pl created by Joshua Wills at 12:45:07 on Fri Sep 19 2003. 


my $curdir = ".";

#constants
my $INT = 0;
my $VOID = 1;
my $STRING = 2;

#functions to ignore in parsing ecmdClientCapi.H because they don't get implemented in the dll, client only functions in ecmdClientCapi.C
my @ignores = qw( ecmdLoadDll ecmdUnloadDll ecmdCommandArgs ecmdQueryTargetConfigured ecmdDisplayDllInfo InitExtension);
my $ignore_re = join '|', @ignores;

# These are functions that should not be auto-gened into ecmdClientCapiFunc.C hand created in ecmdClientCapi.C
my @no_gen = qw( ecmdEnableRingCache ecmdDisableRingCache);
my $no_gen_re = join '|', @no_gen;

# These are functions that are ring cache enabled
my @dont_flush_sdcache = qw( Query Cache Output Error Spy ecmdGetGlobalVar ecmdSetTraceMode Latch);
my $dont_flush_sdcache_re = join '|', @dont_flush_sdcache;
 
my $printout;
my $DllFnTable;
my @enumtable;

open IN, "${curdir}/$ARGV[0]ClientCapi.H" or die "Could not find $ARGV[0]ClientCapi.H: $!\n";

open OUT, ">${curdir}/$ARGV[0]DllCapi.H" or die $!;
print OUT "/* The following has been auto-generated by makedll.pl */\n";

print OUT "#ifndef $ARGV[0]DllCapi_H\n";
print OUT "#define $ARGV[0]DllCapi_H\n\n";

print OUT "#include <inttypes.h>\n";
print OUT "#include <vector>\n";
print OUT "#include <string>\n";
print OUT "#include <ecmdStructs.H>\n";
print OUT "#include <ecmdReturnCodes.H>\n";
print OUT "#include <ecmdDataBuffer.H>\n\n\n";
if ($ARGV[0] ne "ecmd") {
  print OUT "#include <$ARGV[0]Structs.H>\n";
}

print OUT "extern \"C\" {\n\n";

if ($ARGV[0] eq "ecmd") {

  print OUT "/* Dll Common load function - verifies version */\n";
  print OUT "uint32_t dllLoadDll (const char * i_version, uint32_t debugLevel);\n";
  print OUT "/* Dll Specific load function - used by Cronus/GFW to init variables/object models*/\n";
  print OUT "uint32_t dllInitDll ();\n\n";
  print OUT "/* Dll Common unload function */\n";
  print OUT "uint32_t dllUnloadDll ();\n";
  print OUT "/* Dll Specific unload function - deallocates variables/object models*/\n";
  print OUT "uint32_t dllFreeDll();\n\n";
  print OUT "/* Dll Common Command Line Args Function*/\n";
  print OUT "uint32_t dllCommonCommandArgs(int*  io_argc, char** io_argv[]);\n";
  print OUT "/* Dll Specific Command Line Args Function*/\n";
  print OUT "uint32_t dllSpecificCommandArgs(int*  io_argc, char** io_argv[]);\n\n";

} else {
  print OUT "/* Extension initialization function - verifies version */\n";
  print OUT "uint32_t dll".ucfirst($ARGV[0])."InitExtension (const char * i_version);\n\n";
}

#parse file spec'd by $ARGV[0]
while (<IN>) {

    if (/^(uint32_t|std::string|void|bool|int)/) {
	

	next if (/$ignore_re/o);

	my $type_flag = $INT;
	$type_flag = $VOID if (/^void/);
	$type_flag = $STRING if (/^std::string/);

	chomp; chop;  
	my ($func, $args) = split /\(|\)/ , $_;

	my ($type, $funcname) = split /\s+/, $func;
	my @argnames = split /,/ , $args;

        #remove the default initializations
        foreach my $i (0..$#argnames) {
            if ($argnames[$i] =~ /=/) {
              $argnames[$i] =~ s/=.*//;
            }
        }
        $" = ",";


        my $enumname;
        my $orgfuncname = $funcname;

        # WE never want to include a main function if it is in there
        next if ($funcname eq "main");

        if ($funcname =~ /ecmd/) {

           $funcname =~ s/ecmd//;

           $enumname = "ECMD_".uc($funcname);

           $funcname = "dll".$funcname;
        }
        else {

           $enumname = "ECMD_".uc($funcname);
           $funcname = "dll".ucfirst($funcname);
        }

	push @enumtable, $enumname;

        print OUT "$type $funcname(@argnames); \n\n";

	next if (/$no_gen_re/o);

        $printout .= "$type $orgfuncname(@argnames) {\n\n";

	
	$printout .= "  $type rc;\n\n" unless ($type_flag == $VOID);

	$printout .= "#ifndef ECMD_STATIC_FUNCTIONS\n\n";
	$printout .= "  if (dlHandle == NULL) {\n";
        $printout .= "    fprintf(stderr,\"$funcname: eCMD Function called before DLL has been loaded\\n\");\n";
        $printout .= "    exit(ECMD_DLL_INVALID);\n";
	$printout .= "  }\n\n";


	$printout .= "#endif\n\n";

        if ($ARGV[0] ne "ecmd") {
          $printout .= "  if (!".$ARGV[0]."Initialized) {\n";
          $printout .= "    fprintf(stderr,\"$funcname: eCMD Extension not initialized before function called\\n\");\n";
          $printout .= "    fprintf(stderr,\"$funcname: OR eCMD $ARGV[0] Extension not supported by plugin\\n\");\n";
          $printout .= "    exit(ECMD_DLL_INVALID);\n";
          $printout .= "  }\n\n";
        }

        #Put the debug stuff here
	if (!($orgfuncname =~ /ecmdOutput/)) {
	    $printout .= "#ifndef ECMD_STRIP_DEBUG\n";

	    # new debug10 parm tracing stuff
	    if(!($orgfuncname =~ /ecmdFunctionParmPrinter/)) {
		if($#argnames >=0) {
		    $printout .= "  if (ecmdClientDebug >= 8) {\n";
		    $printout .= "     std::vector< void * > args;\n";


#		    $printout .= "     ecmdFunctionParmPrinter(ECMD_FPP_FUNCTIONIN,\"$type $orgfuncname(@argnames)\"";

		    #
#		    my $pp_argstring;
#		    my $pp_typestring;
		    foreach my $curarg (@argnames) {

			my @pp_argsplit = split /\s+/, $curarg;

			my @pp_typeargs = @pp_argsplit[0..$#pp_argsplit-1];
			$tmptypestring = "@typeargs";

			my $tmparg = $pp_argsplit[-1];
			if ($tmparg =~ /\[\]$/) {
			    chop $tmparg; chop $tmparg;
			    $tmptypestring .= "[]";
			}

#			$pp_typestring .= $tmptypestring . ", ";
#			$pp_argstring .= $tmparg . ", ";
			$printout .= "     args.push_back((void*) &" . $tmparg . ");\n";
		    }

#		    chop ($pp_typestring, $pp_argstring);
#		    chop ($pp_typestring, $pp_argstring);
#		    $printout .= "," . $pp_argstring . ");\n\n";
		    $printout .= "     ecmdFunctionParmPrinter(ECMD_FPP_FUNCTIONIN,\"$type $orgfuncname(@argnames)\",args);\n";
		    $printout .= "  }\n";
		} # end if there are no args
	    } # end if its not ecmdFunctionParmPrinter 
	    $printout .= "#endif\n\n";
	}

	unless (/$dont_flush_sdcache_re/o) {
  

	    if ($type_flag == $STRING) {
		$printout .= "   if (ecmdRingCacheEnabled) return ecmdGetErrorMsg(ECMD_RING_CACHE_ENABLED);\n";
	    }
	    elsif ($type_flag == $INT) {
		$printout .= "   if (ecmdRingCacheEnabled) return ECMD_RING_CACHE_ENABLED;\n";
	    }
	    else { #type is VOID
		$printout .= "   if (ecmdRingCacheEnabled) return;\n";
	    }

	}
	
	$printout .= "#ifdef ECMD_STATIC_FUNCTIONS\n\n";

	$printout .= "  rc = " unless ($type_flag == $VOID);

	$" = " ";
       
	if ($type_flag == $VOID) {
	    $printout .= "  ";
	}

	$printout .= $funcname . "(";

	my $argstring;
	my $typestring;
	foreach my $curarg (@argnames) {

	    my @argsplit = split /\s+/, $curarg;

	    my @typeargs = @argsplit[0..$#argsplit-1];
	    $tmptypestring = "@typeargs";

	    my $tmparg = $argsplit[-1];
	    if ($tmparg =~ /\[\]$/) {
		chop $tmparg; chop $tmparg;
		$tmptypestring .= "[]";
	    }

	    $typestring .= $tmptypestring . ", ";
	    $argstring .= $tmparg . ", ";
	}

	chop ($typestring, $argstring);
	chop ($typestring, $argstring);

	$printout .= $argstring . ");\n\n";
	    
	$printout .= "#else\n\n";
	
	


        if ($ARGV[0] ne "ecmd") {
          $DllFnTable = "$ARGV[0]DllFnTable";
        } else {
          $DllFnTable = "DllFnTable";
        }

	$printout .= "  if (".$DllFnTable."[$enumname] == NULL) {\n";
	$printout .= "     ".$DllFnTable."[$enumname] = (void*)dlsym(dlHandle, \"$funcname\");\n";

	$printout .= "     if (".$DllFnTable."[$enumname] == NULL) {\n";

        $printout .= "       fprintf(stderr,\"$funcname : Unable to find $funcname function, must be an invalid DLL - program aborting\\n\"); \n";
        $printout .= "       exit(ECMD_DLL_INVALID);\n";

	$printout .= "     }\n";
	
	$printout .= "  }\n\n";

	$printout .= "  $type (*Function)($typestring) = \n";
	$printout .= "      ($type(*)($typestring))".$DllFnTable."[$enumname];\n\n";

	$printout .= "  rc = " unless ($type_flag == $VOID);
	$printout .= "   (*Function)($argstring);\n\n" ;
	
	$printout .= "#endif\n\n";


        #Put the debug stuff here
        if (!($orgfuncname =~ /ecmdOutput/)) {
	    $printout .= "#ifndef ECMD_STRIP_DEBUG\n";


	    # new debug10 parm tracing stuff
	    if(!($orgfuncname =~ /ecmdFunctionParmPrinter/)) {
		if($#argnames >=0) {
		    $printout .= "  if (ecmdClientDebug >= 8) {\n";
		    $printout .= "     std::vector< void * > args;\n";

		    #
#		    my $pp_argstring;
#		    my $pp_typestring;

		    @argnames = split /,/ , $args;

                    #remove the default initializations
                    foreach my $i (0..$#argnames) {
                       if ($argnames[$i] =~ /=/) {
                          $argnames[$i] =~ s/=.*//;
		       }
	            }
	            $" = ",";

		    foreach my $curarg (@argnames) {

			my @pp_argsplit = split /\s+/, $curarg;

			my @pp_typeargs = @pp_argsplit[0..$#pp_argsplit-1];
			$tmptypestring = "@typeargs";

			my $tmparg = $pp_argsplit[-1];
			if ($tmparg =~ /\[\]$/) {
			    chop $tmparg; chop $tmparg;
			    $tmptypestring .= "[]";
			}

#			$pp_typestring .= $tmptypestring . ", ";
#			$pp_argstring .= $tmparg . ", ";
			$printout .= "     args.push_back((void*) &" . $tmparg . ");\n";
		    }
		    $printout .= "     args.push_back((void*) &rc);\n" unless ($type_flag == $VOID);

#		    chop ($pp_typestring, $pp_argstring);
#		    chop ($pp_typestring, $pp_argstring);

		    $printout .= "\n";

		    $printout .= "     ecmdFunctionParmPrinter(ECMD_FPP_FUNCTIONOUT,\"$type $orgfuncname(@argnames)\",args);\n";
		    #	    
		    $printout .= "   }\n";
		} # end if there are no args
	    } # end if its not ecmdFunctionParmPrinter 

	    $printout .= "#endif\n\n";
        }

	$printout .= "  return rc;\n\n" unless ($type_flag == $VOID);

	$printout .= "}\n\n";

    }

}
close IN;

print OUT "} //extern C\n\n";
print OUT "#endif\n";
print OUT "/* The previous has been auto-generated by makedll.pl */\n";

close OUT;  #ecmdDllCapi.H

open OUT, ">${curdir}/$ARGV[0]ClientEnums.H" or die $!;

print OUT "/* The following has been auto-generated by makedll.pl */\n\n";
print OUT "#ifndef $ARGV[0]ClientEnums_H\n";
print OUT "#define $ARGV[0]ClientEnums_H\n\n";
print OUT "#ifndef ECMD_STATIC_FUNCTIONS\n";

if ($ARGV[0] eq "ecmd") {
  push @enumtable, "ECMD_COMMANDARGS"; # This function is handled specially because it is renamed on the other side

}
push @enumtable, uc($ARGV[0])."_NUMFUNCTIONS";


$" = ",\n";
print OUT "/* These are used to lookup cached functions symbols */\n";
print OUT "typedef enum {\n@enumtable\n} $ARGV[0]FunctionIndex_t;\n\n";
print OUT "#endif\n\n";
print OUT "#endif\n";
$" = " ";

close OUT;  #ecmdClientEnums.H

open OUT, ">${curdir}/$ARGV[0]ClientCapiFunc.C" or die $!;

print OUT "/* The following has been auto-generated by makedll.pl */\n\n";
print OUT "#include <stdio.h>\n\n";
if ($ARGV[0] ne "ecmd") {
  print OUT "#include <ecmdClientCapi.H>\n";
}
print OUT "#include <$ARGV[0]ClientCapi.H>\n";
print OUT "#include <$ARGV[0]ClientEnums.H>\n\n\n";

print OUT "#include <ecmdUtils.H>\n\n";

print OUT "#ifndef ECMD_STATIC_FUNCTIONS\n";
print OUT "\n #include <dlfcn.h>\n\n";

if ($ARGV[0] eq "ecmd") {
  print OUT " void * dlHandle = NULL;\n";
  print OUT " void * DllFnTable[".uc($ARGV[0])."_NUMFUNCTIONS];\n";
} else {
  print OUT "/* This is from ecmdClientCapiFunc.C */\n";
  print OUT " extern void * dlHandle;\n";
  print OUT " void * $ARGV[0]DllFnTable[".uc($ARGV[0])."_NUMFUNCTIONS];\n";

  print OUT "/* Our initialization flag */\n";
}       

print OUT "\n#else\n\n";

print OUT " #include <$ARGV[0]DllCapi.H>\n\n";

print OUT "#endif\n\n\n";

if ($ARGV[0] ne "ecmd") {
  print OUT " bool $ARGV[0]Initialized = false;\n";
}

print OUT "#ifndef ECMD_STRIP_DEBUG\n";
print OUT "extern int ecmdClientDebug;\n";
print OUT "#endif\n\n\n";

print OUT "extern int ecmdRingCacheEnabled;\n\n\n";


print OUT $printout;

print OUT "/* The previous has been auto-generated by makedll.pl */\n";

close OUT;  #ecmdClientCapiFunc.C
