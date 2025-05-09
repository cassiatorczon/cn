module CF = Cerb_frontend
module A = CF.AilSyntax
module C = CF.Ctype
module AT = ArgumentTypes
module LAT = LogicalArgumentTypes
module CtA = Fulminate.Cn_to_ail
module Utils = Fulminate.Utils
module FExtract = Fulminate.Extract
module Config = TestGenConfig

let debug_log_file : out_channel option ref = ref None

let init_debug () =
  if Option.is_none !debug_log_file && !Cerb_debug.debug_level > 0 then
    debug_log_file
    := Some
         (let open Stdlib in
          open_out "generatorCompilation.log")


let debug_log (str : string) : unit =
  init_debug ();
  match !debug_log_file with
  | Some oc ->
    output_string oc str;
    flush oc
  | None -> ()


let debug_stage (stage : string) (str : string) : unit =
  debug_log (stage ^ ":\n");
  debug_log (str ^ "\n\n")


let compile_constant_tests
      (sigma : CF.GenTypes.genTypeCategory A.sigma)
      (insts : FExtract.instrumentation list)
  : Test.t list * Pp.document
  =
  let test_names, docs =
    List.map_split
      (fun (inst : FExtract.instrumentation) ->
         ( Test.
             { kind = Constant;
               suite =
                 inst.fn_loc
                 |> Cerb_location.get_filename
                 |> Option.get
                 |> Filename.basename
                 |> String.split_on_char '.'
                 |> List.hd;
               test = Sym.pp_string inst.fn
             },
           let open Pp in
           (if not (Config.with_static_hack ()) then
              CF.Pp_ail.(
                with_executable_spec
                  (fun () ->
                     pp_function_prototype
                       inst.fn
                       (let _, _, decl =
                          List.assoc Sym.equal inst.fn sigma.declarations
                        in
                        decl))
                  ())
              ^^ hardline
            else
              empty)
           ^^ CF.Pp_ail.pp_statement
                A.(
                  Utils.mk_stmt
                    (AilSexpr
                       (Utils.mk_expr
                          (AilEcall
                             ( Utils.mk_expr (AilEident (Sym.fresh "CN_UNIT_TEST_CASE")),
                               [ Utils.mk_expr (AilEident inst.fn) ] ))))) ))
      insts
  in
  let open Pp in
  (test_names, separate (twice hardline) docs ^^ twice hardline)


let compile_generators
      (filename : string)
      (sigma : CF.GenTypes.genTypeCategory A.sigma)
      (prog5 : unit Mucore.file)
      (insts : FExtract.instrumentation list)
  : Pp.document
  =
  let ctx = GenCompile.compile prog5.resource_predicates insts in
  debug_stage "Compile" (ctx |> GenDefinitions.pp_context |> Pp.plain ~width:80);
  let ctx = ctx |> GenInline.inline in
  debug_stage "Inline" (ctx |> GenDefinitions.pp_context |> Pp.plain ~width:80);
  let ctx = ctx |> GenNormalize.normalize prog5 in
  debug_stage "Normalize" (ctx |> GenDefinitions.pp_context |> Pp.plain ~width:80);
  let ctx = ctx |> GenDistribute.distribute in
  debug_stage "Distribute" (ctx |> GenDefinitions.pp_context |> Pp.plain ~width:80);
  let ctx = ctx |> GenOptimize.optimize prog5 in
  debug_stage "Optimize" (ctx |> GenDefinitions.pp_context |> Pp.plain ~width:80);
  let ctx = ctx |> GenRuntime.elaborate in
  debug_stage "Elaborated" (ctx |> GenRuntime.pp |> Pp.plain ~width:80);
  ctx |> GenCodeGen.compile filename sigma


let convert_from ((x, ct) : Sym.t * C.ctype) =
  CF.Pp_ail.pp_expression
    (Utils.mk_expr
       (CtA.wrap_with_convert_from
          A.(
            AilEmemberofptr
              ( Utils.mk_expr (AilEident (Sym.fresh "res")),
                CF.Symbol.Identifier
                  ( Locations.other __LOC__,
                    Sym.pp_string (GenUtils.get_mangled_name [ x ]) ) ))
          (Memory.bt_of_sct (Sctypes.of_ctype_unsafe (Locations.other __LOC__) ct))))


let compile_random_test_case
      (sigma : CF.GenTypes.genTypeCategory A.sigma)
      (prog5 : unit Mucore.file)
      ((test, inst) : Test.t * FExtract.instrumentation)
  : Pp.document
  =
  let open Pp in
  let args =
    let _, _, _, xs, _ = List.assoc Sym.equal inst.fn sigma.function_definitions in
    match List.assoc Sym.equal inst.fn sigma.declarations with
    | _, _, Decl_function (_, _, cts, _, _, _) ->
      List.combine xs (List.map (fun (_, ct, _) -> ct) cts)
    | _ ->
      failwith
        (String.concat
           " "
           [ "Function declaration not found for"; Sym.pp_string inst.fn; "@"; __LOC__ ])
  in
  let globals =
    let global_syms =
      let args = args |> List.map fst in
      inst.internal
      |> Option.get
      |> AT.get_lat
      |> LAT.free_vars (fun _ -> Sym.Set.empty)
      |> Sym.Set.to_seq
      |> List.of_seq
      |> List.filter (fun x ->
        not
          (List.mem (fun x y -> String.equal (Sym.pp_string x) (Sym.pp_string y)) x args))
    in
    List.map
      (fun sym ->
         match List.assoc Sym.equal sym prog5.globs with
         | GlobalDecl sct -> (sym, sct)
         | GlobalDef (sct, _) -> (sym, sct))
      global_syms
  in
  (if not (Config.with_static_hack ()) then
     CF.Pp_ail.(
       with_executable_spec
         (fun () ->
            pp_function_prototype
              inst.fn
              (let _, _, decl = List.assoc Sym.equal inst.fn sigma.declarations in
               decl))
         ())
     ^^ hardline
   else
     empty)
  ^^ (if List.is_empty globals then
        string "CN_RANDOM_TEST_CASE"
      else (
        let init_name = string "cn_test_gen_" ^^ Sym.pp inst.fn ^^ string "_init" in
        string "void"
        ^^ space
        ^^ init_name
        ^^ parens
             (string "struct"
              ^^ space
              ^^ string (String.concat "_" [ "cn_gen"; Sym.pp_string inst.fn; "record" ])
              ^^ star
              ^^ space
              ^^ string "res")
        ^^ space
        ^^ braces
             (nest
                2
                (hardline
                 ^^ separate_map
                      hardline
                      (fun (sym, sct) ->
                         let ty =
                           CF.Pp_ail.(
                             with_executable_spec
                               (pp_ctype ~is_human:false C.no_qualifiers)
                               (Sctypes.to_ctype sct))
                         in
                         Sym.pp sym
                         ^^ space
                         ^^ equals
                         ^^ space
                         ^^ star
                         ^^ parens (ty ^^ star)
                         ^^ string "convert_from_cn_pointer"
                         ^^ parens
                              (string "res->"
                               ^^ Sym.pp (GenUtils.get_mangled_name [ sym ]))
                         ^^ semi
                         ^^ hardline
                         ^^ string "cn_assume_ownership"
                         ^^ parens
                              (separate
                                 (comma ^^ space)
                                 [ ampersand ^^ Sym.pp sym;
                                   string "sizeof" ^^ parens ty;
                                   string "(char*)" ^^ dquotes init_name
                                 ])
                         ^^ semi)
                      globals)
              ^^ hardline)
        ^^ twice hardline
        ^^ string "CN_RANDOM_TEST_CASE_WITH_INIT"))
  ^^ parens
       (separate
          (comma ^^ space)
          [ string test.suite;
            string test.test;
            int (Config.get_num_samples ());
            separate_map (comma ^^ space) convert_from args
          ])
  ^^ semi
  ^^ twice hardline


let compile_generator_tests
      (sigma : CF.GenTypes.genTypeCategory A.sigma)
      (prog5 : unit Mucore.file)
      (insts : FExtract.instrumentation list)
  : Test.t list * Pp.document
  =
  let tests =
    List.map
      (fun (inst : FExtract.instrumentation) ->
         Test.
           { kind = Generator;
             suite =
               inst.fn_loc
               |> Cerb_location.get_filename
               |> Option.get
               |> Filename.basename
               |> String.split_on_char '.'
               |> List.hd;
             test = Sym.pp_string inst.fn
           })
      insts
  in
  let open Pp in
  (tests, concat_map (compile_random_test_case sigma prog5) (List.combine tests insts))
