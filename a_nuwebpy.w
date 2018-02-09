m4_include(inst.m4)m4_dnl
\documentclass[twoside]{rapport3}
\newcommand{\theTitle}{m4_doctitle}
\newcommand{\theAuthor}{m4_author}
\input{thelatexheader.tex}
\begin{document}
\maketitle
\tableofcontents

\chapter{The program}
\label{chap:the-program}

\section{Invocation of the program; arguments}
\label{sec:invocation}

The program can be started with a command like:
\begin{alltt}
  nuweb.py [flags] nuweb-file
\end{alltt}

\begin{description}
\item[-h:] Print usage message.
\item[-r, --hyperlinks:] Use Hyperlinks.
\item[-t, --no-tex:] No \TeX{} .
\end{description}

@d usage-message function @{@%
def usage():
@%    sys.stderr.write('%s $Revision: 8a3bacdfb376 $\n' % sys.argv[0])
    sys.stderr.write('usage: nuweb.py [flags] nuweb-file\n')
    sys.stderr.write('flags:\n')
    sys.stderr.write('-h, --help:              '
        + 'output this message\n')
    sys.stderr.write('-r, --hyperlinks:        '
        + 'generate hyperlinks\n')
    sys.stderr.write('-t, --no-tex:            '
        + 'don\'t generate the LaTeX output\n')
@| @}

Other flags from the original Nuweb have not yet been implemented.
The following two variables remember the flags that have been used:

@d  option flag variables @{
global hyperlinks
hyperlinks = False
generate_document = True

@| hyperlinks generate_document @}

Parse the command-line options using the \verb|getopt| package.

@d packages list @{ getopt@| getopt@}


@d parse commandline options @{
@< option flag variables @>

@< usage-message function @>

try:
    opts, args = getopt.getopt\
    (sys.argv[1:],
        "hrt",
         ["help", "hyperlinks", "no-tex", ])
except getopt.GetoptError:
    usage()
    sys.exit(1)

@|opts args @}

Check out the options:

@d parse commandline options @{@%
for o, v in opts:
    if o in ("-h", "--help"):
        usage()
        sys.exit(0)
    elif o in ("-r", "--hyperlinks"):
        hyperlinks = True
    elif o in ("-t", "--no-tex"):
        generate_document = False
@| @}

Put the name of the nuweb file in  \verb|input_filename|. Append suffix \verb|.w| to it if the user has not done that.

@d parse commandline options @{@%
if len(args) != 1:
    usage()
    sys.exit(1)
arg = args[0]

if arg[-2:] == ".w":
    input_filename = arg
    basename = arg[:-2]
else:
    input_filename = arg + ".w"
    basename = arg

@|input_filename @}

\section{Digesting a nuweb file}
\label{sec:digest-nuweb-file}

\subsection{Text-elements and code-elements}
\label{sec:code-text-pieces}

A nuweb file consists essentially of an alternation of (\LaTeX{}) texts and
code-fragments. The nuweb program dis-assembles the input nuweb file
and puts each chunk of text or code in an object of a sub-class of 
\verb|DocumentElement|. 

@d DocumentElement class and children @{@%
class DocumentElement():
    """The abstract root of the element classes that make up the
    document. The document is a sequence of Text, Code and Index
    elements."""
    def generate_code(self):
        pass
    def generate_latex(self, output):
        output.write(self.text)
    def matches(self, identifier):
        return False
    def defined_by(self):
        """Returns a list of other Fragments with the same name, ie
        which taken together define the whole fragment."""
        return []
    def referenced_in(self):
        """Returns a list of CodeElements which reference this
        Fragment."""
        return []
    def used_identifiers(self):
        """Returns a list of the identifier definitions made by this
        CodeElement and their users: [[identifier, [element]]]."""
        return []
    def uses_identifiers(self):
        """Returns a list of all the identifier definitions made by
        other CodeElements and used in this one:
        [[identifier-text, [element]]]."""
        return []

@|DocumentElement @}


Chunks of \LaTeX{} text are simple to handle. They are just stored in
objects in the reading phase and written out (using method
\verb|generate_latex|) in the document output phase. While reading
from the input-file, convert double at-characters into single at-characters.

@d DocumentElement class and children @{@%
class Text(DocumentElement):
    """Contains LaTeX text from the original nuweb source file."""
    def __init__(self, text):
        self.text = re.sub(r'@@@@', '@@', text)
@|Text @}


@d DocumentElement class and children @{

@< the CodeElement class @>
@% @< subclasses of the CodeElement class @>


@| @}


Chunks of code are more complicated. We have the \verb|CodeElement|
class in which we store the following
properties of a chunk of code:

\begin{description}
\item[Nature :] is it a macro or a direct part of the output-file.
\item[Name :] of the file or the macro.
\item[Lines :] The code itself.
\item[Identifiers :] The list of identifiers defined by the element
  (expressed as \verb|[[identifier-text, Identifier]]|)
\item[Literal text :] the joined content of the LiteralLines (to speed
    up identifier search).
\item[Splittable :] Whether the text may be split over a page boundary.
\end{description}

To split up the code chunk into it's elements, we can use the
following regexp \verb|element_matcher|. When it matches the following
elements are available in the match-group:

\begin{description}
\item[kind :] \verb|o|, \verb|O|, \verb|d| or \verb|D| (file or
  macro).
\item[name :] filename or macro-name.
\item[text :] The chunk of code.
\item[identifiers :] List of the identifiers (found between \verb+@@|+ and \verb|@@}|).
\end{description}

@d regexp element\_matcher to split up a chunk of code @{@%
# Matches a CodeElement for factory(). Take care not to recognise
# '@@@@|' or terminate early on "@@@@}" (unusual, but occurs in
# nuweb.w).
element_matcher = re.compile(r'(?s)'
                             + r'@@(?P<kind>[oOdD])'
                             + r'\s*'
                             + r'(?P<name>.*?)'
                             + r'@@{(?P<text>.*?)'
                             + r'((?<!@@)@@\|(?P<identifiers>.*))?'
                             + r'(?<!@@)@@}')

@|element_matcher @}

The \verb|CodeElement| class has separate subclasses \verb|File| and
\verb|Fragment| to chunks of code that belong directly to a file
resp. define macro's.


@d the CodeElement class @{@%
class CodeElement(DocumentElement):
    """May be a File or a Fragment.
    - 'name' is either the file name or the definition name.
    - 'lines' is the code (scrap) content, which is a list of CodeLines.
    - 'identifiers' is a list of the identifiers defined by the element
             expressed as [[identifier-text, Identifier]].
    - 'literal_text' is the joined content of the LiteralLines (to speed
             up identifier search).
    - 'splittable' is True if the text is allowed to be split over a
             page boundary in the printed document (otherwise a minipage
             environment is used to prevent splitting)."""
    @< variables in the CodeElement class @>
    @< methods in the CodeElement class @>
@|CodeElement @}

The input file reader extracts the complete text of a chunk of code
(from the \verb|@@[oOdD| instruction to the finishing \verb|@@}|) and 
and generates a new object of one of the
subclasses of \verb|CodeElement| with the following ``factory''
method. 

@d methods in the CodeElement class @{@%
@@staticmethod
def factory(segment):
    """Given a segment of the document that corresponds to a File or
    Fragment, this factory function determines the kind, name, text
    and identifiers and returns an initialized CodeElement of the
    right kind."""
    @< extract the elements of the code-chunk or die @>

    @< return the proper File or Fragment object @(o@,File@,False@) @>
    @< return the proper File or Fragment object @(O@,File@,True@) @>
    @< return the proper File or Fragment object @(d@,Fragment@,False@) @>
    @< return the proper File or Fragment object @(D@,Fragment@,True@) @>
@%    if kind == 'o':
@%        return File(name, text, identifiers, False)
@%    elif kind == 'O':
@%        return File(name, text, identifiers, True)
@%    elif kind == 'd':
@%        return Fragment(name, text, identifiers, False)
@%    elif kind == 'D':
@%        return Fragment(name, text, identifiers, True)

@|factory @}


Analyse the code chunk with the \verb|element_matcher| regexp. If this
is not possible, abort the program. Otherwise, fill in the variables
\verb|kind|, \verb|name|, \verb|text| and \verb|identifiers|.

@d extract the elements of the code-chunk or die @{
@< regexp element\_matcher to split up a chunk of code @>
@%    m = re.match(CodeElement.element_matcher, segment)
m = re.match(element_matcher, segment)
try:
    kind = m.group('kind')
    name = m.group('name').strip()
    text = m.group('text')
    if m.group('identifiers'):
        identifiers = m.group('identifiers').split()
    else:
        identifiers = []
except:
    sys.stderr.write("failed CodeElement.factory(%s)\n" % segment)
    sys.exit(1)
@| @}



Return a File or Fragment object, dependent of the type of the code chunk:
@d return the proper File or Fragment object @{@%
if kind == '@1':
    return @2(name, text, identifiers, @3)
@| @}


@< return a File or Fragment object @>



@d variables in the CodeElement class @{@%
# The scrap sequence number, used as the index (key) to
# code_elements.
scrap_number = 1

@|element_matcher scrap_number @}

@d methods in the CodeElement class @{@%
    def __lt__(self, other):
        """Sort by scrap number."""
        return self.scrap_number < other.scrap_number

@|__lt__ @}


@d the CodeElement class @{@%
    @@staticmethod
    def write_elements(stream, elements):
        """'elements' is a list of CodeElements whose page/scrap-on-page
        references are to be written to 'stream'."""
        # Start with an impossible page number
        page = -1
        for e in elements:
            try:
                if e.page_number != page and page != -1:
                    # Insert a ', ' separator for new pages after the
                    # first.
                    stream.write(", ")
                new_page = e.page_number
                new_scrap = e.scrap_on_page
            except:
                # Ths happens if the page and scrap data hasn't been
                # set up (probably because there's no .aux file, but
                # maybe because it's too short; perhaps (e.g.) there's
                # nuweb code after the \end{document}).
                global need_to_rerun
                need_to_rerun = True
                new_page = '?'
                new_scrap = '?'
                stream.write(", ")
            # Write the link target.
            stream.write("\\NWlink{nuweb%s%s}"
                         % (new_page, new_scrap))
            if new_page != page:
                # This is a new page, so include the page number in
                # the link.
                stream.write("{%s%s}" % (new_page, new_scrap))
            else:
                # This is a further element on the same page, so the
                # link is just the scrap-on-page.
                stream.write("{%s}" % new_scrap)
            # Update the page number.
            page = new_page

@| @}

@d the CodeElement class @{@%
    def __init__(self, name, text, identifiers, splittable):
        """'name' is either the file name or the fragment name.
        'text' is the code (scrap) content.
        'identifiers' is a list of the identifiers defined by the scrap.
        'splittable' is True if the text is allowed to be printed over
        a page boundary in the printed document."""

        self.name = name

        # We want to split into lines, retaining the \n at the end of
        # all lines that have one already (which may not include the
        # last, or only, line).
        # We do this by making sure that all line terminators are \n\r
        # (NB, not the normal order) and splitting on \r.
        # We rely on Python to generate \r\n on output if required.
        text = re.sub(r'\r', '', text)
        text = re.sub(r'\n', r'\n\r', text)
        # We need to keep the trailing \n, if there is one, but not to
        # get an extra empty line because of the split on the trailing
        # \r.
        if len(text) > 0 and text[-1] == '\r':
            text = text[:-1]
        self.lines = [CodeLine.factory(l) for l in text.split("\r")]

        # We keep the raw text (but only of LiteralLines) to speed up
        # searching for identifiers.
        self.literal_text = ''.join([l.text for l in self.lines
                                     if isinstance(l, LiteralCodeLine)])

        self.identifiers = [[i, Identifier.factory(i)] for i in identifiers]
        self.splittable = splittable
        self.scrap_number = CodeElement.scrap_number
        CodeElement.scrap_number = CodeElement.scrap_number + 1
        code_elements[self.scrap_number] = self
@| @}

@d the CodeElement class @{@%

    def __repr__(self):
        """Provide a printable representation (only for debugging)."""
        return "%s/%d" % (self.name, self.scrap_number)
@| @}

@d the CodeElement class @{@%
    def write_code(self, stream, indent, parameters = []):
        """Output the code to 'stream', indenting all lines after the
        first by 'indent', and skipping the last line if it's
        blank."""
        self.lines[0].write_code(stream, '', parameters)
        for l in self.lines[1:]:
            l.write_code(stream, indent, parameters)

@| @}

@d the CodeElement class @{@%
    def generate_latex(self, output):
        output.write("\\begin{flushleft} \\small\n")
        if not self.splittable:
            output.write("\\begin{minipage}{\\linewidth}")
        output.write("\\label{scrap%d}\\raggedright\\small\n"
                     % self.scrap_number)
        self.write_title(output)
        output.write("\\vspace{-1ex}\n")
        output.write("\\begin{list}{}{} \\item\n")
        for l in self.lines:
            l.write_latex(output)
        output.write("\\mbox{}{\NWsep}\n")
        output.write("\\end{list}\n")
        output.write("\\vspace{-1ex}\n")
        defined_by = self.defined_by()
        used_identifiers = self.used_identifiers()
        uses_identifiers = self.uses_identifiers()
        if len(defined_by) > 1 \
                or isinstance(self, Fragment) \
                or len(used_identifiers) > 0 \
                or len(uses_identifiers) > 0:
            # We only create this list environment for the
            # crossreferences if there are any (otherwise, we'd have
            # to create an empty \item). There's always at least one
            # item for a Fragment (either 'referenced in' or 'never
            # referenced').
            output.write("\\vspace{-1ex}\n")
            output.write("\\footnotesize\n")
            output.write("\\begin{list}{}{")
            output.write("\\setlength{\\itemsep}{-\\parsep}")
            output.write("\\setlength{\\itemindent}{-\\leftmargin}")
            output.write("}\n")

            def write_id_and_uses(i):
                output.write("\\verb@@`'%s@@\\ " % i[0])
                if len(i[1]) > 0:
                    CodeElement.write_elements(output, sorted(i[1]))
                else:
                    output.write("\\NWtxtIdentsNotUsed")

            if len(defined_by) > 1:
                output.write("\\item \\NWtxtMacroDefBy\\ ")
                CodeElement.write_elements(output, sorted(defined_by))
                output.write(".\n")

            if isinstance(self, Fragment):
                referenced_in = self.referenced_in()
                if len(referenced_in) > 0:
                    output.write("\\item \\NWtxtMacroRefIn\\ ")
                    CodeElement.write_elements(output, sorted(referenced_in))
                    output.write(".\n")
                else:
                    output.write("\\item \\NWtxtMacroNoRef.\n")

            if len(used_identifiers) > 0:
                output.write("\\item \\NWtxtIdentsDefed\\ ")
                for i in used_identifiers[:-1]:
                    write_id_and_uses(i)
                    output.write(", ")
                write_id_and_uses(used_identifiers[-1])
                output.write(".\\\\\n")

            if len(uses_identifiers) > 0:
                output.write("\\item \\NWtxtIdentsUsed\\ ")
                for i in uses_identifiers[:-1]:
                    write_id_and_uses(i)
                    output.write(", ")
                write_id_and_uses(uses_identifiers[-1])
                output.write(".\\\\\n")

            output.write("\\end{list}\n")
        if not self.splittable:
            output.write("\\end{minipage}\n")
        output.write("\\end{flushleft}\n")

@| @}

@d the CodeElement class @{@%
    def referenced_in(self):
        """Returns a list of CodeElements which reference this
        Fragment."""
        def invokes_self(code_lines):
            for l in code_lines:
                if l.invokes(self.name):
                    return True;
            return False;
        # A Fragment that's referenced but not defined has no code
        # lines, so don't include it.
        return [e for e in document
                if isinstance(e, CodeElement) \
                    and hasattr(e, 'lines') \
                    and invokes_self(e.lines)]

@| @}

@d the CodeElement class @{@%
    def used_identifiers(self):
        """Returns a list of the identifier definitions made by this
        CodeElement and their users (except for those that also define
        the identifier): [[identifier-text, [element]]]."""
        code = [c for c in document
                if isinstance(c, CodeElement) and c != self]
        result = []
        for i in self.identifiers:
            elements = []
            for c in code:
                if i[1].matches(c.literal_text) \
                   and not c.defines_identifier(i[0]):
                    elements.append(c)
            result.append([i[0], elements])
        return sorted(result)

@| @}

@d the CodeElement class @{@%
    def uses_identifiers(self):
        """Returns a list of all the identifier definitions made by other
        CodeElements and used in this one (except those that are also
        defined in this one): [[identifier-text, [element]]]."""
        code = [c for c in document
                if isinstance(c, CodeElement) and c != self]
        matches = {}
        for c in code:
            for i in c.identifiers:
                if i[1].matches(self.literal_text) \
                   and not self.defines_identifier(i[0]):
                    value = matches.get(i[0], [])
                    value.append(c)
                    matches[i[0]] = value
        return [[k, matches[k]] for k in sorted(matches.keys())]

@| @}

@d the CodeElement class @{@%
    def defines_identifier(self, id):
        """Return True if the Element defines the identifier id."""
        for i in self.identifiers:
            if id == i[0]: return True
        return False
@| @}




\subsection{Read the nuweb file}
\label{sec:read-nuwebfile}

A nuweb file consists essentially of an alternation of (\LaTeX{}) texts and
code-fragments. The function \verb|read_nuweb| converts these
text-chunks and code-chunks in an alternation of objects of the resp.\
\verb|DocumentElements| and \verb|DocumentElement| class and
concatenates these in a list named \verb|document|. Apart from the
texts and code-fragments, there are the instructions \verb|@@`'%|,
\verb|@@i| and the index requests that have to be taken care of.

@d global variables in nuweb.py @{@%
@% # In 'document', we have the input document as a sequence of
@% # DocumentElements.
document = []
@|document @}

To open and read the input file, the function \verb|read_nuweb| uses a
subclass of the \verb|File| class, named \verb|InputFile|. This
subclass takes care of the \verb|@@`'%|
characters, so we don't have to bother with them here.
The function
reads the nuweb file line by line. To read the file, the function uses
\verb||InputFile|, a subclass of \verb|file| that skips comment tails
(from \verb|@@`'%| until/including end-of-line).


@d functions in nuweb.py @{
def read_nuweb(path):
    """Reads the .w file specified at 'path' (and any other files
    included using @@i), forming a sequence of DocumentElements held in
    'document'."""
    global document
    try:
        input = InputFile(path, 'r')
    except:
        sys.stderr.write("couldn't open %s for input.\n" % path)
        sys.exit(1)
    @< parse the input text @>
    sys.stderr.write("file %s has %d lines.\n"
                     % (input.path, input.line_number))
    input.close()
@| @}


In a loop, the function reads a chunk of text until it encounters a
macro definition or an index request (like \verb|@@f|). Each chunk of
text is packed in an object of class \verb|DocumentElement| that is
appended to a list \verb|document|. Macro definitions are stored in
objects of class \verb|CodeElement| and appended to \verb|document| as
well.

I do not yet completely understand how the function handles \verb|@@i| commands.

The following regexps find \verb|@@i| commands and macro definition commands. 

@d regexps in read\_nuweb @{
look_for_includefile = re.compile(r'(?<!@@)@@i\s*(?P<filename>\S*)')
look_for_begin_codefragment = re.compile(r'(?<!@@)@@[oOdD]')
look_for_index_request = re.compile(r'\s*@@[fmu]\s*')
@|look_for_includefile  look_for_begin_codefragment @}


@d parse the input text @{
@< regexps in read\_nuweb @>
latex_text = ''
while True:
    line = input.readline()
    if input.at_end:
        break
    if look_for_includefile.search(line):
        m = re.match(r'@@i\s*(?P<filename>\S*)', line)
        read_nuweb(m.group('filename'))
    elif look_for_begin_codefragment.search(line):
        @< digest a macro definition @>
    elif look_for_index_request.match(line):
        # To be recognised, an index request needs to be on a line
        # of its own.
        @< digest an index request @>
    else:
        latex_text = latex_text + line
# Save the last LaTeX text
document.append(Text(latex_text))
@| @}


When a macro-definition (like \verb|@@d|) has been encountered, store
the \LaTeX{} text before the definition, read the complete definition
and store it in a \verb|CodeElement| object. Start a
\verb|latex_text| block to catch the following \LaTeX{} text.

@d digest a macro definition @{@%
m = re.match(r'(?s)(?P<text>.*)(?P<start>(?<!@@)@@[oOdD].*)', line)
latex_text = latex_text + m.group('text')
# Save the LaTeX text
document.append(Text(latex_text))
element_text = ''
line = m.group('start')
# We have to avoid premature termination at a line
# containing '@@@@}' (unusual, but nuweb.w has this).
while not re.search(r'(?<!@@)@@}', line):
    element_text = element_text + line
    line = input.readline()
    if input.at_end:
        sys.stderr.write("file %s ended within fragment.\n"
                         % input.path)
        sys.exit(1)
n = re.match(r'(?P<fragment>.*@@})(?P<text>.*)', line)
element_text = element_text + n.group('fragment')
document.append(CodeElement.factory(element_text))
latex_text = n.group('text')
@| @}


When an index request is found (command \verb|@@f|, \verb|@@m| or
\verb|@@u| at the beginning of a line), store the \LaTeX{} code before
the request in a \verb|DocumentElement| and store the request itself
in an \verb|Index| object. 

@d digest an index request @{@%
document.append(Text(latex_text))
latex_text = ""
n = re.match(r'\s*@@(?P<index>[fmu])\s*', line)
document.append(Index.factory(n.group('index')))
@| @}




\subsection{A class to read the input-file}
\label{sec:inputfileclass}

@d classes for file i/o @{@%
class InputFile(file):
    """Supports iteration over an input file, eating all occurrences
    of at-percent (but not at-at-percent) from the occurrence's
    position to the newline (or end-of-file).

    Because a commented-out line can appear to have zero length,
    end-of-file is indicated by the public instance variable
    'at_end'."""

    at_percent_matcher = re.compile(r'(?s)(?<!@@)@@`'%.*$')

    def __init__(self, path, mode='r'):
        file.__init__(self, path, mode)
        self.at_end = False
        self.line_number = 0
        self.path = path

    def readline(self):
        l = file.readline(self)
        self.at_end = len(l) == 0
        self.line_number = self.line_number + 1
        return re.sub(InputFile.at_percent_matcher, '', l)
@| @}

\section{Miscellaneous}
\label{sec:misc}



\section{Remainder of the program}
\label{sec:remainder}


@o nuweb.py @{@%
#!/usr/bin/python

#  Copyright (C) Simon Wright <simon@@pushface.org>

#  This package is free software; you can redistribute it and/or
#  modify it under terms of the GNU General Public License as
#  published by the Free Software Foundation; either version 2, or
#  (at your option) any later version. This package is distributed in
#  the hope that it will be useful, but WITHOUT ANY WARRANTY; without
#  even the implied warranty of MERCHANTABILITY or FITNESS FOR A
#  PARTICULAR PURPOSE. See the GNU General Public License for more
#  details. You should have received a copy of the GNU General Public
#  License distributed with this package; see file COPYING.  If not,
#  write to the Free Software Foundation, 59 Temple Place - Suite
#  330, Boston, MA 02111-1307, USA.

@%import getopt, re, sys, tempfile, time
import re, tempfile, time, sys,@< packages list @>


#-----------------------------------------------------------------------
# Notes
#-----------------------------------------------------------------------

# Makes considerable use of Python's extensions to regular
# expressions, see http://docs.python.org/library/re.html. For
# example, including (?s) in an RE is equivalent to the flag
# re.DOTALL, which allows "." to match \n (newline).

#-----------------------------------------------------------------------
# Globals
#-----------------------------------------------------------------------
@< global variables in nuweb.py @>

# In 'code_elements' we have all the CodeElements (keyed by scrap
# number).
code_elements = {}

# In 'files', the keys are the output file names, the values are the
# output streams.
files = {}

# 'hyperlinks', if True, means that cross-references are to be
# generated as hyperlinks using the hyperref package (which needs to
# be specified in your document).
hyperlinks = False

# 'need_to_rerun', if True, means we end with a message telling the
# user she needs to re-run nuweb.py after running LaTeX (because of a
# scrap number mismatch).
need_to_rerun = False

#-----------------------------------------------------------------------
# Nuweb file i/o
#-----------------------------------------------------------------------
@< classes for file i/o @>



class OutputCodeFile:
    """The contents are written to a temporary file (nw* in the
    current directory). When the file is closed, the contents are
    compared to an existing file of the desired name, if any. If there
    is no change, the existing file is left unchanged; if the file
    doesn't already exist, or has changed, the new contents are
    written to it.

    Also ensures that trailing white space is eliminated from all code
    output files. This is really just for neatness, but in the case of
    GCC Ada, the standard style checks (-gnaty) warn about trailing
    white space (which, incidentally, includes non-zero-length blank
    lines)."""

    def __init__(self, path):
        self.path = path
        self.tempfile = tempfile.TemporaryFile(dir=".", prefix="nw")
        self.buffer = ''

    def write(self, text):
        nl = text.find("\n")
        if nl >= 0:
            self.tempfile.write((self.buffer + text[:nl]).rstrip())
            self.tempfile.write("\n")
            self.buffer = ''
            self.write(text[nl + 1:])
        else:
            self.buffer = self.buffer + text

    def close(self):
        if len(self.buffer) > 0:
            # The '\n' ensures the buffer is flushed.
            self.write("\n")
        self.tempfile.seek(0)
        new_content = self.tempfile.readlines()
        self.tempfile.close()
        try:
            outfile = open(self.path, "r")
            current_content = outfile.readlines()
            outfile.close()
            if new_content == current_content:
                #sys.stderr.write("output file %s unchanged.\n" % self.path)
                return
            else:
                sys.stderr.write("output file %s has changed.\n" % self.path)
        except:
            sys.stderr.write("creating output file %s.\n" % self.path);
        try:
            outfile = open(self.path, "w")
            outfile.writelines(new_content)
            outfile.close()
        except:
            sys.stderr.write("unable to create output file %s.\n" % self.path)


#-----------------------------------------------------------------------
# CodeLine class and children
#-----------------------------------------------------------------------

class CodeLine():
    """A CodeLine is a line of code text from a File or Fragment,
    including any terminating \n."""

    # Regexes for matching fragment invocations and any parameters
    # while reading in. Note, at this time only the old-style
    # bracketed parameterisation is handled.
    invocation_matcher = re.compile(r'(?s)'
                                    + r'(?P<start>.*)'
                                    + r'@@<'
                                    + r'(?P<invocation>.*?)'
                                    + r'@@>'
                                    + r'(?P<end>.*)')
    parameter_matcher = re.compile(r'(?P<fragment>.*)'
                                   + r'(@@\((?P<parameters>.*)@@\))')

    @@staticmethod
    def factory(line):
        # We know at this point that there are no \r's in the line, so
        # it's safe to replace '@@@@' by '\r', thus avoiding any
        # potential problems with eg @@@@<.
        line = re.sub(r'@@@@', r'\r', line)
        if re.match(CodeLine.invocation_matcher, line):
            return InvokingCodeLine(line)
        else:
            return LiteralCodeLine(line)

    @@staticmethod
    def substitute_parameters(l, parameters):
        """Replace each occurrence in 'l' of '@@[1..9]' with the
        corresponding element of 'parameters'."""
        for j in range(len(parameters)):
            l = l.replace("@@`'%d" % (j + 1), parameters[j])
        return l

    @@staticmethod
    def substitute_at_symbols_for_code(str):
        """Unescape @@<char> for code output."""

        # We don't have to handle '@@(', '@@,', '@@1', which will have
        # been processed as part of an invocation.

        # At the moment, we just deal with the emboldening indication
        # '@@_'.

        # @@-sequences with simple substitutions:
        for s in [["@@_", ""]]:
            str = str.replace(s[0], s[1])

        # Replace the '@@@@' marker '\r' with a single '@@'
        str = str.replace('\r', '@@')

        return str

    @@staticmethod
    def substitute_at_symbols_for_latex(str):
        """Unescape @@' etc for LaTeX output."""

        # Un-escape @@' etc.
        for s in [["@@'", "'"], ["@@,", ","], ["@@#", ""]]:
            str = str.replace(s[0], s[1])

        # Parameters like '@@1' must appear as themselves, which is
        # slightly awkward because the LaTeX output is embedded in
        # \verb@@...@@. Any @@ we want to appear in the output is
        # inserted by terminating the current \verb@@ environment,
        # including a \verb|@@|, and restarting the verb@@ environment.
        str = re.sub(r'@@([1-9])', r'@@\\verb|@@|\\verb@@\1', str)

        # embolden text surrounded by '@@_'.
        str = re.sub(r'@@_(.*?)@@_',
                     r'@@{\\sffamily\\bfseries \1}\\verb@@',
                     str)

        # Replace any '\r' markers by a single '@@' (see above for why
        # this is a bit tricky)
        str = re.sub(r'\r', r'@@\\verb|@@|\\verb@@', str)

        return str

    def write_code(self, stream, indent, parameters):
        """Writes self to 'stream' as code, indented by 'indent'. To
        be overridden."""
        pass

    def write_latex(self, stream):
        """Writes self to 'stream' as LaTeX. To be overridden."""
        pass

    def invokes(self, candidate):
        """Returns True if the CodeLine invokes the fragment
        'candidate'."""
        return False

class LiteralCodeLine(CodeLine):
    """A line of code that contains text but no fragment invocations."""

    def __init__(self, line):
        self.text = line

    def write_code(self, stream, indent, parameters):
        """Writes self to 'stream' as code, indented by 'indent', with
        substitution of 'parameters'."""
        # '@@#' (at the start of the text) means don't indent.
        text = CodeLine.substitute_parameters(self.text, parameters)
        if re.match(r'@@#', text):
            text = text[2:]
            indent = ""
        text = CodeLine.substitute_at_symbols_for_code(text)
        stream.write("%s%s" % (indent, text))

    def write_latex(self, stream):
        """Writes self to 'stream' as LaTeX."""
        # Remove any trailing '\n' (XXX is this right?)
        text = re.sub(r'\n', '', self.text)
        text = CodeLine.substitute_at_symbols_for_latex(text)
        stream.write("\\mbox{}\\verb@@`'%s@@\\\\\n" % text)

class InvokingCodeLine(CodeLine):
    """A line of code that contains a fragment invocation."""
    # XXX only supports one invocation! They might be nested!

    def __init__(self, line):
        m = re.match(CodeLine.invocation_matcher, line)
        fragment = m.group('invocation').strip()
        p = re.match(CodeLine.parameter_matcher, fragment)
        if p:
            fragment = p.group('fragment').strip()
            parameters = re.split(r'\s*@@,\s*',
                                  p.group('parameters').strip())
        else:
            parameters = []
        self.start = m.group('start')
        self.fragment = fragment
        self.parameters = parameters
        self.end = m.group('end')

    def write_code(self, stream, indent, parameters):
        """Writes self to 'stream' as code, indented by 'indent'."""
        start = CodeLine.substitute_at_symbols_for_code(self.start)
        end = CodeLine.substitute_at_symbols_for_code(self.end)
        stream.write("%s%s" % (indent, start))
        params = [CodeLine.substitute_parameters(p, parameters)
                  for p in self.parameters]
        # Note the indent needed for the fragments (where we are now;
        # the input indent was where we began, and we've now added the
        # characters in the self.start sequence).
        new_indent = indent +  re.sub(r'\S', ' ', start).expandtabs()
        fragments = [d for d in document if d.matches(self.fragment)]
        # Fix up abbreviated names in the invocation.
        # XXX Fixing up stuff on the fly probably doesn't help the
        # XXX reader's understanding!
        for f in fragments:
            if len(f.name) > len(self.fragment):
                self.fragment = f.name
        if len(fragments) == 0:
            sys.stderr.write("no fragments matching '%s'.\n" % self.fragment)
        else:
            fragments[0].write_code(stream, new_indent, params)
            for f in fragments[1:]:
                # For follow-on fragments, we have to output the new
                # indentation at the beginning of the new line. NB,
                # this assumes that if there is anything in self.end,
                # there'll only be ome matching fragment.
                stream.write(new_indent)
                f.write_code(stream, new_indent, params)
        stream.write(end)

    def write_latex(self, stream):
        """Writes self to 'stream' as LaTeX."""

        # We need to find all the fragments which match this
        # invocation.

        # If there are none, no action (I suppose we could output
        # a warning?).

        # Otherwise, we output a page/scrap-on-page link just
        # before the closing >.

        # If there is only one the link is to that fragment.

        # If there are more than one, the link is to the first,
        # followed by ', ...'

        # Assumption: only one invocation on a line!

        # Check whether the invocation includes parameters, and
        # form the LaTeX text accordingly.
        if len(self.parameters) > 0:
            parameters = [CodeLine.substitute_at_symbols_for_latex(p)
                          for p in self.parameters]
            text = r'{\itshape %s}\ (\verb@@`'%s@@)' % (self.fragment,
                                                    ", ".join(parameters))
        else:
            text = r'{\itshape %s}' % self.fragment
        # Find all the elements with the invoked name
        elements = [e for e in document if e.matches(self.fragment)]
        if len(elements) > 0:
            e = elements[0]
            try:
                link = '%s%s' % (e.page_number, e.scrap_on_page)
            except:
                link = '??'
            link = r'{\footnotesize \NWlink{nuweb%s}{%s}}' % (link, link)
        else:
            link = r'{\footnotesize (not found)}'
        if len(elements) > 1:
            link = link + r',\ ...'
        # Reconstitute the line, making substitutions.
        line = CodeLine.substitute_at_symbols_for_latex(self.start) \
            + r'@@$\langle\,$' \
            + text \
            + r'\ ' \
            + link \
            + r'\,$\rangle\,$\verb@@' \
            + CodeLine.substitute_at_symbols_for_latex \
                (re.sub(r'\n', '', self.end))

        # Output the line.
        stream.write("\\mbox{}\\verb@@`'%s@@\\\\\n" % line)

    def invokes(self, candidate):
        """Returns True if the InvokingCodeLine invokes the fragment
        'candidate'."""
        # XXX Need some 'matches' logic here (though perhaps we should
        # expand all fragment names in an earlier pass???)
        return candidate == self.fragment


#-----------------------------------------------------------------------
# Identifier class and children
#-----------------------------------------------------------------------

class Identifier():
    """The abstract root of the user-defined identifier classes."""

    @@staticmethod
    def factory(match):
        if re.match(r'[a-zA-Z0-9_.]+$', match):
            return NormalIdentifier(match)
        else:
            return AbnormalIdentifier(match)

    def matches(self, text):
        """'line' is a code line (or, for a parameterised invocation,
        a parameter)."""
        return False

class NormalIdentifier(Identifier):
    """A NormalIdentifier consists of alphanumerics, underscore or
    period. It will match text that contains the match text supplied
    provided it isn't surrounded by any text that could itself form
    part of a NormalIdentifier (except period)."""

    def __init__(self, match):
        self.match = re.compile(r'(^|[^a-zA-Z0-9_])' \
                                    + re.escape(match) \
                                    + r'($|[^a-zA-Z0-9_])')

    def matches(self, text):
        return re.search(self.match, text)

class AbnormalIdentifier(Identifier):
    """An AbnormalIdentifier contains at least one character that
    isn't allowed in a NormalIdentifier. It will match text that
    contains the match text, so may cause problems with ambiguity (for
    example, 'here$' would match a line containing 'there$')."""

    def __init__(self, match):
        self.match = re.compile(re.escape(match))

    def matches(self, text):
        return re.search(self.match, text)


#-----------------------------------------------------------------------
# DocumentElement class and children
#-----------------------------------------------------------------------
@< DocumentElement class and children @>


class File(CodeElement):
    """Forms part of a named file. The whole file is composed of all
    the File objects with the same name, concatenated in document
    order."""

    def __init__(self, name, text, identifiers, splittable):
        """The 'name' consists of a filename (without spaces) and
        optional flags."""
        name_parts = name.split()
        CodeElement.__init__(self,
                             name_parts[0],
                             text,
                             identifiers,
                             splittable)
        self.flags = name_parts[1:]

    def generate_code(self):
        if not self.name in files:
            files[self.name] = OutputCodeFile(self.name)
        self.write_code(files[self.name], '')

    def write_title(self, output):
        try:
            link = "%s%s" % (self.page_number, self.scrap_on_page)
        except:
            link = "??"
        output.write("\\NWtarget{nuweb%s}{}\\verb@@\"%s\"@@"
                     "\\nobreak\\ {\\footnotesize{%s}}$\\equiv$\n"
                     % (link, self.name, link))

class Fragment(CodeElement):
    """Forms part of a definition. The whole definition is composed of
    all the Fragments with the same name, in document order."""

    def matches(self, invocation):
        if self.name == invocation:
            return True
        elif invocation[-3:] == '...' \
                and self.name[:len(invocation)-3] == invocation[:-3]:
            return True
        elif self.name[-3:] == '...' \
                and invocation[:len(self.name)-3] == self.name[:-3]:
            # This covers the case where the invocation is the full name.
            self.name = invocation
            return True
        else:
            return False

    def write_title(self, output):
        try:
            link = "%s%s" % (self.page_number, self.scrap_on_page)
        except:
            link = "??"
        output.write("\\NWtarget{nuweb%s}{}$\\langle\\,${\\itshape %s}"
                     "\\nobreak\\ {\\footnotesize{%s}}$\\,\\rangle\\equiv$\n"
                     % (link, self.name, link))

    def defined_by(self):
        """Returns a list of all the Fragments with the same name, ie
        which taken together define the whole fragment."""
        return [d for d in document if d.matches(self.name)]


#-----------------------------------------------------------------------
# Index class and children
#-----------------------------------------------------------------------

class Index(DocumentElement):
    """Outputs an index."""

    @@staticmethod
    def factory(id):
        """Creates and returns the appropriate type of Index given the
        'id'."""
        return {
            'f' : lambda: FileIndex(),
            'm' : lambda: MacroIndex(),
            'u' : lambda: IdentifierIndex()
            }[id]()

    def generate_latex(self, output):
        """To be overridden."""
        pass

class FileIndex(Index):
    """Outputs an index of all the files specified in the document,
    with the elements that define them."""

    def generate_latex(self, output):
        start = time.clock()

        # 'files' is a dictionary keyed by file-name, whose values are
        # lists of the CodeElements which define them.
        files = {}

        for d in document:
            if isinstance(d, File):
                value = files.get(d.name, [])
                value.append(d)
                files[d.name] = value

        if len(files) > 0:
            output.write("{\\small\\begin{list}{}{")
            output.write("\\setlength{\\itemsep}{-\\parsep}")
            output.write("\\setlength{\\itemindent}{-\\leftmargin}")
            output.write("}\n")

            for f in sorted(files.keys()):
                output.write("\\item \\verb@@\"%s\"@@" % f)
                output.write(" {\\footnotesize \\NWtxtDefBy\ ")
                CodeElement.write_elements(output, files[f])
                output.write(".}\n")

            output.write("\\end{list}}\n")

        sys.stderr.write("generating the file index took %.3gs.\n"
                         % (time.clock() - start))

class MacroIndex(Index):
    """Outputs an index of all the fragments in the docment, stating
    where defined and where used."""

    def generate_latex(self, output):
        start = time.clock()

        # 'definitions' is a dictionary keyed by fragment-name,
        # whose values are lists of the CodeElements that define them.
        definitions = {}

        for d in document:
            if isinstance(d, Fragment):
                defs = definitions.get(d.name, [])
                defs.append(d)
                definitions[d.name] = defs

        if len(definitions) > 0:
            output.write("{\\small\\begin{list}{}{")
            output.write("\\setlength{\\itemsep}{-\\parsep}")
            output.write("\\setlength{\\itemindent}{-\\leftmargin}")
            output.write("}\n")

            for d in sorted(definitions.keys()):
                output.write("\\item $\\langle\\,$%s\\nobreak\\ " % d)
                output.write("{\\footnotesize ")
                CodeElement.write_elements(output, sorted(definitions[d]))
                output.write("}$\\,\\rangle$ ")
                output.write("{\\footnotesize ")

                # 'uses' is a list of the CodeElements that reference
                # this Fragment.
                uses = definitions[d][0].referenced_in()
                if len(uses) > 0:
                    output.write("{\\NWtxtRefIn} ")
                    CodeElement.write_elements(output, sorted(uses))
                else:
                    output.write("{\\NWtxtNoRef}")
                output.write(".}\n")

            output.write("\\end{list}}\n")

        sys.stderr.write("generating the macro index took %.3gs.\n"
                         % (time.clock() - start))

class IdentifierIndex(Index):

    def generate_latex(self, output):
        start = time.clock()

        # 'definitions' is a dictionary keyed by identifier-text,
        # whose values are lists of the CodeElements that define them.
        definitions = {}

        # 'users' is a dictionary keyed by identifier-text, whose
        # values are lists of the CodeElements that use them.
        users = {}

        for d in document:
            if isinstance(d, CodeElement):
                for usage in d.used_identifiers():

                    identifier = usage[0]
                    uses = usage[1]

                    value = definitions.get(identifier, [])
                    value.append(d)
                    definitions[identifier] = value

                    value = users.get(identifier, [])
                    for u in uses:
                        if not u in value:
                            value.append(u)
                    users[identifier] = value

        if len(users) > len(definitions):
            sys.stderr.write("more identifiers are used than are defined!\n")

        if len(definitions) > 0:
            output.write("{\\small\\begin{list}{}{")
            output.write("\\setlength{\\itemsep}{-\\parsep}")
            output.write("\\setlength{\\itemindent}{-\\leftmargin}")
            output.write("}\n")

            for i in sorted(definitions.keys()):
                output.write("\\item \\verb@@`'%s@@" % i)
                output.write(": {\\NWtxtIdentDefinedIn} {\\footnotesize ")
                CodeElement.write_elements(output, sorted(definitions[i]))
                output.write("}, ");
                if len(users[i]) > 0:
                    output.write("{\\NWtxtIdentUsedIn} {\\footnotesize ");
                    CodeElement.write_elements(output, sorted(users[i]))
                    output.write("}");
                else:
                    output.write("{\\NWtxtIdentsNotUsed}")
                output.write(".\n");

            output.write("\\end{list}}\n")

        sys.stderr.write("generating the identifier index took %.3gs.\n"
                         % (time.clock() - start))


#-----------------------------------------------------------------------
# Main and utilities
#-----------------------------------------------------------------------

@< functions in nuweb.py @>

    
def read_aux(path):
    """LaTeX generates <basename>.aux, which contains (inter alia) the
    page on which each \label{} occurs. Nuweb generates a label for
    each scrap (\label{scrapnnn}; the first time through (when no .aux
    file is found) and when the number of scraps increases, we report
    that nuweb needs to be re-run. Of course, the same will be true if
    a scrap ends up on a different page, so this is more of a hint
    than an 'if and only if' indication.

    Once we know whch page a scrap is on, and which scrap it is on
    that page, we can create the proper cross-reference."""

    global code_elements, need_to_rerun

    try:
        input = open(path, 'r')
    except:
        need_to_rerun = True
        return

    page = -1  # impossible value

    for l in input:
        # Be explicit about the expected format; the memoir
        # documentclass has a complicated form with nested braces for
        # the {} section before the page number.
        m = re.match(r'\\newlabel{scrap(?P<scrap>\d+)}{{.*}{(?P<page>\d+)}'
                     + r'{.*}{.*}{.*}}', l)
        if m:
            scrap = int(m.group('scrap'))
            p = m.group('page')
            if p == page:
                scrap_on_page = chr(ord(scrap_on_page) + 1)
            else:
                page = p
                scrap_on_page = 'a'
            try:
                code_elements[scrap].page_number = page
                code_elements[scrap].scrap_on_page = scrap_on_page
            except:
                need_to_rerun = True


def main():

    @< parse commandline options @>
@%    global hyperlinks
@%
@%    generate_document = True
@%
@%    @< usage-message function @>
@%
@%@%    def usage():
@%@%        sys.stderr.write('%s $Revision: 8a3bacdfb376 $\n' % sys.argv[0])
@%@%        sys.stderr.write('usage: nuweb.py [flags] nuweb-file\n')
@%@%        sys.stderr.write('flags:\n')
@%@%        sys.stderr.write('-h, --help:              '
@%@%                 + 'output this message\n')
@%@%        sys.stderr.write('-r, --hyperlinks:        '
@%@%                 + 'generate hyperlinks\n')
@%@%        sys.stderr.write('-t, --no-tex:            '
@%@%                 + 'don\'t generate the LaTeX output\n')
@%
@%    try:
@%        opts, args = getopt.getopt\
@%            (sys.argv[1:],
@%            "hrt",
@%            ["help", "hyperlinks", "no-tex", ])
@%    except getopt.GetoptError:
@%        usage()
@%        sys.exit(1)
@%
@%    for o, v in opts:
@%        if o in ("-h", "--help"):
@%            usage()
@%            sys.exit(0)
@%        elif o in ("-r", "--hyperlinks"):
@%            hyperlinks = True
@%        elif o in ("-t", "--no-tex"):
@%            generate_document = False
@%
@%    if len(args) != 1:
@%        usage()
@%        sys.exit(1)
@%    arg = args[0]
@%
@%    if arg[-2:] == ".w":
@%        input_filename = arg
@%        basename = arg[:-2]
@%    else:
@%        input_filename = arg + ".w"
@%        basename = arg

    read_nuweb(input_filename)
    if generate_document:
        read_aux(basename + '.aux')

    # We need to resolve the abbreviated fragment references.

    # This code handles references where the full form is found in one
    # of the fragment definitions. The case where the full form
    # appears in a fragment invocation only is handled in
    # Fragment.matches(). Note that, in that case, the error of having
    # multiple possible expansions probably won't be detected.
    #
    # Personally, I'd like to remove fragment name abbreviation; it's
    # a recipe for subtle errors.
    for d in document:
        if isinstance(d, Fragment):
            if d.name[-3:] == '...':
                replacement = []
                for e in document:
                    if isinstance(e, Fragment) \
                            and e != d \
                            and e.name[-3:] != '...' \
                            and e.name[:len(d.name)-3] == d.name[:-3] :
                        if not e.name in replacement:
                            replacement.append(e.name)
                if len(replacement) > 1:
                    sys.stderr.write\
                        ("multiple expansions for definition \"%s\".\n"
                         % d.name)
                    sys.exit(1)
                elif len(replacement) == 1:
                    d.name = replacement[0]

    # Nuweb has a flag -o which suppresses code output. This
    # implementation handles some processing (expansion of abbreviated
    # fragment references) on the fly during code generation, so that
    # feature has been omitted. In any case, code generation is much
    # quicker than document generation, so the gain would be minimal.

    start = time.clock()

    for d in document:
        d.generate_code()
    for f in files.values():
        f.close()

    sys.stderr.write("generating the code took %.3gs.\n"
                     % (time.clock() - start))

    if not generate_document:
        return

    start = time.clock()

    # We check for CodeElements that are the only ones on their page;
    # if that's the case, we clear scrap_on_page, so that the scrap
    # link is, for example, '7' instead of '7b'.
    code = [c for c in document if isinstance(c, CodeElement)]
    try:
        for j, c in enumerate(code):
            if c.scrap_on_page == 'a':
                # NB short-circuit evaluation
                if (j + 1 == len(code)
                    or c.page_number != code[j + 1].page_number):
                    c.scrap_on_page = ''
    except:
        pass

    doc = open(basename + ".tex", "w")

    def define_macro(stream, macro, definition):
        stream.write("\\newcommand{\\%s}{%s}\n" % (macro, definition))

    if hyperlinks:
        doc.write ("%s\n"
                   % "\\newcommand{\\NWtarget}[2]{\\hypertarget{#1}{#2}}")
        doc.write ("%s\n" % "\\newcommand{\\NWlink}[2]{\\hyperlink{#1}{#2}}")
    else:
        doc.write ("%s\n" % "\\newcommand{\\NWtarget}[2]{#2}")
        doc.write ("%s\n" % "\\newcommand{\\NWlink}[2]{#2}")

    define_macro (doc, "NWtxtMacroDefBy", "Fragment defined by")
    define_macro (doc, "NWtxtMacroRefIn", "Fragment referenced in")
    define_macro (doc, "NWtxtMacroNoRef", "Fragment never referenced")
    define_macro (doc, "NWtxtDefBy", "Defined by")
    define_macro (doc, "NWtxtRefIn", "Referenced in")
    define_macro (doc, "NWtxtNoRef", "Not referenced")
    define_macro (doc, "NWtxtFileDefBy", "File defined by")
    define_macro (doc, "NWtxtIdentDefinedIn", "defined in")
    define_macro (doc, "NWtxtIdentUsedIn", "used in")
    define_macro (doc, "NWtxtIdentsDefed", "Defines:")
    define_macro (doc, "NWtxtIdentsNotUsed", "never used")
    define_macro (doc, "NWtxtIdentsUsed", "Uses:")
    define_macro (doc, "NWsep", "${\\diamond}$")
    define_macro (doc, "NWnotglobal", "(not defined globally)")
    define_macro (doc, "NWuseHyperlinks", "")

    for d in document:
        d.generate_latex(doc)

    doc.close()

    sys.stderr.write("generating the LaTeX took %.3gs overall.\n"
                     % (time.clock() - start))

    if need_to_rerun:
        sys.stderr.write('Need to re-run nuweb.py after running latex.\n')


if __name__ == '__main__':
    main()

@| @}



\section{Indexes}
\label{sec:indexes}


\subsection{Filenames}
\label{sec:filenames}

@f

\subsection{Macro's}
\label{sec:macros}

@m

\subsection{Variables}
\label{sec:veriables}

@u

\end{document}
