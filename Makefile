
.SUFFIXES: .pdf .w .tex .html .aux .log .php
.PHONY : html

figfiles=$(shell ls *.fig)
figbases=$(basename $(figfiles))

#
# PDF figures
#

pdft_names=$(foreach fil,$(figbases), $(fil).pdftex_t)
pdf_fig_names=$(foreach fil,$(figbases), $(fil).pdftex)

%.pdftex: %.fig
	fig2dev -L pdftex $< > $@

.PRECIOUS : %.pdftex
%.pdftex_t: %.fig %.pdftex
	fig2dev -L pdftex_t -p $*.pdftex $< > $@

%.pdf : %.w $(W2PDF) $(pdf_fig_names) $(pdft_names)
	chmod 775 $(W2PDF)
	$(W2PDF) $*

#
# HTML
#
hfigfiles=$(foreach fil, $(figfiles), html/$(fil))

pst_names=$(foreach fil, $(figbases), html/$(fil).pstex_t)
psfig_names=$(foreach fil, $(figbases), html/$(fil).pstex)



html/%.pstex : %.fig
	fig2dev -L pstex $< > $@

html/%.pstex_t : %.fig html/%.pstex
	fig2dev -L pstex_t -p html/$*.pstex $*.fig > $@

html/nuwebpy.w : nuwebpy.w
	cd html && ln -fs ../nuwebpy.w .


# cd html && ln -s ../$< .



m4_nuwebpy.w : a_nuwebpy.w
	gawk '{if(match($$0, "@%")) {printf("%s", substr($$0,1,RSTART-1))} else print}' $< \
          | gawk '{gsub(/[\\][\$$]/, "$$");print}'  > $@

nuwebpy.w : m4_nuwebpy.w 
	m4 -P $< > $@


sources : nuwebpy.w
	nuweb nuwebpy.w

pdf : nuwebpy.w  $(pdf_fig_names) $(pdft_names)
	./w2pdf $<

# html : $(hfigfiles)

html : $(psfig_names) $(pst_names) html/nuwebpy.w
	mkdir -p html
	cd html && export TEXINPUTS=../: && ./w2html nuwebpy


