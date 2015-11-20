# We need ocamlfind
ifeq (, $(shell which ocamlfind))
$(warning "ocamlfind is required to build the executable part of Cerberus")
endif


BOLD="\033[1m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"

# Looking for Lem
ifdef LEM_PATH
  LEMDIR=$(LEM_PATH)
else
  LEMDIR=~/bitbucket/lem
endif

LEM0=lem -wl ign -wl_rename warn -wl_pat_red err -wl_pat_exh warn \
        -only_changed_output 

LEM=$(LEM0) -outdir $(BUILD_DIR) -add_loc_annots


# C11 related stuff
CMM_MODEL_DIR=concurrency
CMM_MODEL_LEM =\
  cmm_csem.lem

CMM_EXEC_DIR=concurrency
CMM_EXEC_LEM =\
  cmm_op.lem


# The cerberus model
CERBERUS_LEM=\
  cabs.lem \
  dlist.lem \
  constraints.lem \
  cmm_aux.lem \
  boot.lem \
  cabs_to_ail.lem \
  cabs_to_ail_aux.lem \
  cabs_to_ail_effect.lem \
  scope_table.lem \
  std.lem \
  decode.lem \
  multiset.lem \
  core.lem \
  core_aux.lem \
  translation.lem \
  translation_aux.lem \
  translation_effect.lem \
  core_indet.lem \
  core_rewrite.lem \
  core_run.lem \
  core_run_aux.lem \
  errors.lem \
  exception.lem \
  global.lem \
  implementation_.lem \
  loc.lem \
  product.lem \
  state.lem \
  state_operators.lem \
  state_exception.lem \
  symbol.lem \
  undefined.lem \
  core_ctype.lem \
  core_ctype_aux.lem \
  defacto_memory_types.lem \
  defacto_memory.lem \
  mem.lem \
  mem_aux.lem \
  mem_common.lem \
  symbolic.lem \
  driver_util.lem \
  driver_effect.lem \
  driver.lem \
  exception_undefined.lem \
  state_exception_undefined.lem \
  nondeterminism.lem \
  thread.lem \
  uniqueId.lem \
  enum.lem \
  builtins.lem \
  ail/Common.lem \
  ail/ErrorMonad.lem \
  ail/TypingError.lem \
  ail/Range.lem \
  ail/Implementation.lem \
  ail/AilSyntax.lem \
  ail/AilSyntaxAux.lem \
  ail/AilTypes.lem \
  ail/AilTypesAux.lem \
  ail/AilTyping.lem \
  ail/AilWf.lem \
  ail/Context.lem \
  ail/Annotation.lem \
  ail/GenTypes.lem \
  ail/GenTypesAux.lem \
  ail/GenTyping.lem \
  monadic_parsing.lem \
  output.lem



# Where and how ocamlbuild will be called
BUILD_DIR=ocaml_generated

# Create the directory where ocamlbuild will be called, and copy the OCaml library files from Lem.
$(BUILD_DIR):
	@echo $(BOLD)CREATING the OCaml build directory$(RESET)
	@mkdir $(BUILD_DIR)
	@echo $(BOLD)COPYING the Lem ocaml libraries$(RESET)
	@cp $(LEMDIR)/ocaml-lib/*.ml $(LEMDIR)/ocaml-lib/*.mli $(BUILD_DIR)

# Copy the cmm model files to the build dir
copy_cmm: $(addprefix $(CMM_MODEL_DIR)/, $(CMM_MODEL_LEM)) | $(BUILD_DIR)
	@echo $(BOLD)COPYING$(RESET) $(CMM_MODEL_LEM)
	@cp $(addprefix $(CMM_MODEL_DIR)/, $(CMM_MODEL_LEM)) $(BUILD_DIR)

# Copy the cmm executable model files to the build dir
copy_cmm_exec: $(addprefix $(CMM_EXEC_DIR)/, $(CMM_EXEC_LEM)) | $(BUILD_DIR)
	@echo $(BOLD)COPYING$(RESET) $(CMM_EXEC_LEM)
	@cp $(addprefix $(CMM_EXEC_DIR)/, $(CMM_EXEC_LEM)) $(BUILD_DIR)

# Copy the cerberus model files to the build dir
copy_cerberus: $(addprefix model/, $(CERBERUS_LEM)) | $(BUILD_DIR)
	@echo $(BOLD)COPYING cerberus .lem files$(RESET)
	@cp $(addprefix model/, $(CERBERUS_LEM)) $(BUILD_DIR)

#dependencies:
#	@if [ "2" == "$(shell ocamlfind query pprint > /dev/null 2>&1; echo $$?)" ]; then \
#	  $(error "Please install pprint"); \
#	fi
#	mkdir dependencies
#	cd dependencies; make -f ../Makefile.dependencies


lem: copy_cmm copy_cmm_exec copy_cerberus
	@echo $(BOLD)LEM$(RESET) -ocaml *.lem
	@OCAMLRUNPARAM=b $(LEM) -ocaml $(wildcard $(BUILD_DIR)/*.lem) 2>&1 | ./tools/colours.sh lem
	@sed -i"" -e "s/open Operators//" $(BUILD_DIR)/core_run.ml
	@sed -i"" -e "s/open Operators//" $(BUILD_DIR)/driver.ml



DOC_BUILD_DIR = generated_doc

alldoc.tex: copy_cmm copy_cmm_exec copy_cerberus
	@OCAMLRUNPARAM=b $(LEM0) -outdir $(DOC_BUILD_DIR) -cerberus_pp -html -tex_all alldoc.tex -html $(wildcard $(BUILD_DIR)/*.lem) 

alldoc.pdf: alldoc.tex
	pdflatex alldoc.tex
	pdflatex alldoc.tex
#	TEXINPUTS=../lem/tex-lib:$(TEXINPUTS) pdflatex alldoc.tex
#	TEXINPUTS=../lem/tex-lib:$(TEXINPUTS) pdflatex alldoc.tex



ocaml_native:
	@echo $(BOLD)OCAMLBUILD$(RESET) main.native
	@cp src/main.ml src/main.ml_
	@sed s/"<<HG-IDENTITY>>"/"`hg id` -- `date "+%d\/%m\/%Y@%H:%M"`"/ src/main.ml_ > src/main.ml
	@ocamlbuild -j 4 -use-ocamlfind -pkgs pprint,cmdliner,zarith -libs unix,nums,str main.native | ./tools/colours.sh
	@mv src/main.ml_ src/main.ml
	@cp -L main.native cerberus

ocaml_byte:
	@echo $(BOLD)OCAMLBUILD$(RESET) main.d.byte
	@ocamlbuild -j 4 -use-ocamlfind -pkgs pprint,cmdliner,zarith -libs unix,nums,str main.byte | ./tools/colours.sh




# LOS-count the spec

include Makefile-source

los:
	./mysloc   $(addprefix model/,$(SOURCE_ail) )
	./mysloc   $(addprefix model/,$(SOURCE_ail_typing) )
	./mysloc   $(addprefix model/,$(SOURCE_cabs) )
	./mysloc   $(addprefix model/,$(SOURCE_cabs_to_ail) )
	./mysloc   $(addprefix model/,$(SOURCE_core) )
	./mysloc   $(addprefix model/,$(SOURCE_core_to_core) )
	./mysloc   $(addprefix model/,$(SOURCE_core_dynamics) )
	./mysloc   $(addprefix model/,$(SOURCE_elaboration) )
	./mysloc   $(addprefix model/,$(SOURCE_utils) )
	./mysloc   $(addprefix model/,$(SOURCE_defacto)) 
	./mysloc   $(addprefix model/,$(SOURCE_concurrency_interface))


losparser:
	./mysloc \
	parsers/cparser/Cparser_driver.ml  \
	parsers/cparser/Parser_errors.ml   \
	parsers/cparser/Parser_errors.mli  \
	parsers/cparser/tokens.ml
	wc \
	parsers/cparser/Lexer.mll	       \
	parsers/cparser/Parser.mly \
	parsers/cparser/pre_parser.mly    

losconc:
	./mysloc \
	~/rsem/cpp/newmm_op/executableOpsem.lem \
	~/rsem/cpp/newmm_op/minimalOpsem.lem \
	~/rsem/cpp/newmm_op/relationalOpsem.lem 
	wc ~/rsem/cpp/newmm_op/*.thy


los_snapshot-2015-11-20.txt:
	$(MAKE) los > los_snapshot-2015-11-20.txt 


clean:
	rm -rf _build

clear: clean
	rm -rf $(BUILD_DIR)
