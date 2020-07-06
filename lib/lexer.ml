open Std
open Sexplib.Std

type mode = Content_type | Content_type_param

type error = [ `Unexpected_token of string ] [@@deriving sexp_of, variants]

type lb = mode Lex_buffer.t

type result = (Token.t, error) R.t [@@deriving sexp_of]

let rec lex_whitespace (lexer : lb) =
  if Char_code.is_whitespace lexer.ch then (
    Lex_buffer.next lexer;
    lex_whitespace lexer )

(*
 field-content = field-vchar [ 1*( SP / HTAB ) field-vchar ]
 field-value = *( field-content / obs-fold )
 field-vchar = VCHAR / obs-text
*)
let lex_field_value t =
  Lex_buffer.lex_start t;
  let rec lex () =
    if Char_code.is_vchar t.ch then (
      Lex_buffer.next t;
      lex () )
    else if Char_code.is_whitespace t.ch then (
      Lex_buffer.next t;
      lex_whitespace t;
      if Char_code.is_vchar @@ Lex_buffer.peek t then (
        Lex_buffer.next t;
        lex () )
      else
        sprintf
          "Expected token VCHAR in token 'Header_field_value %s' but got '\\%d'"
          (Lex_buffer.lexeme t) t.ch
        |> unexpected_token
        |> R.error )
    else Lex_buffer.lexeme t |> Token.header_field_value |> R.ok
  in
  lex ()

(* token := 1*<any (US-ASCII) CHAR except SPACE, CTLs, or tspecials> *)
let lex_token t =
  Lex_buffer.lex_start t;
  let rec lex () =
    if Char_code.is_token_char t.ch then (
      Lex_buffer.next t;
      lex () )
    else Lex_buffer.lexeme t |> Token.token |> R.ok
  in
  lex ()

(* 
 https://tools.ietf.org/html/rfc5322#section-3

 qtext           = %d33 /             ; Printable US-ASCII
                   %d35-91 /          ;  characters not including
                   %d93-126 /         ;  '\' or the quote character
                   obs-qtext

 qcontent        = qtext / quoted-pair

 quoted-string   = [CFWS]
                   DQUOTE *([FWS] qcontent) [FWS] DQUOTE
                   [CFWS]
*)

(*  
 FWS             =   ([*WSP CRLF] 1*WSP) /  obs-FWS
                                           ; Folding white space
*)
(* let lex_fws t = *)
(*   let rec lex () = *)
(*    lex_whitespace t; *)
(*      if peek t == *)

let lex_quoted_string _t =
  (* quoted-pair = ('\' (VCHAR / WSP)) / obs-qp *)
  ()

let lex_header_param _t = R.ok Token.eof

(* tokenizes HTTP 'Content-Type' header value, eg. multipart/form-data; boundary=7353230 *)
let lex_multipart_header_value (t : lb) =
  if Char_code.is_vchar t.ch then lex_field_value t
  else if t.ch == Char_code.semicolon then (
    Lex_buffer.next t;
    lex_header_param t )
  else R.ok Token.eof

(*--------------------------------------------*)
(*----------------- Unit Tests ---------------*)
(*--------------------------------------------*)

let pp_result r = Sexplib.Sexp.pp_hum Format.std_formatter (sexp_of_result r)

let%expect_test "lex_field_value" =
  [ "gzip, deflate ;"; "feed  "; "text/html ; " ]
  |> List.map (Lex_buffer.create Content_type)
  |> List.iter (lex_field_value >> pp_result);
  [%expect
    {|
    (Header_field_value "gzip, deflate")(Header_field_value feed)(Header_field_value
                                                                  text/html) |}]

let%expect_test "lex_token" =
  [ "boundary ="; "bound\x7Fary"; "boundary"; "boundary    " ]
  |> List.map (Lex_buffer.create Content_type)
  |> List.iter (lex_token >> pp_result);
  [%expect {| (Token boundary)(Token bound)(Token boundary)(Token boundary) |}]
