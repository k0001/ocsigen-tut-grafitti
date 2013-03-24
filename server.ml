open Eliom_content
open Eliom_content.Html5.D
open Common

module Grafitti_app = Eliom_registration.App (struct
  let application_name = "grafitti"
end)


let rgb_from_string color =             (* color is in format "#rrggbb" *)
  let get_color i =
    (float_of_string ("0x"^(String.sub color (1+2*i) 2))) /. 255. in
  try (get_color 0, get_color 2, get_color 2) with _ -> 0., 0., 0.

let launch_server_canvas () =
    let bus = Eliom_bus.create Json.t<messages> in
    let draw_server, image_string =
      let surface = Cairo.image_surface_create
        Cairo.FORMAT_ARGB32 ~width ~height in
      let ctx = Cairo.create surface in
      ((fun ((color : string), size, (x1,y1), (x2,y2)) ->
        Cairo.set_line_width ctx (float size);
        Cairo.set_line_join ctx Cairo.LINE_JOIN_ROUND;
        Cairo.set_line_cap ctx Cairo.LINE_CAP_ROUND;
        let red,green,blue = rgb_from_string color in
        Cairo.set_source_rgb ctx ~red ~green ~blue;
        Cairo.move_to ctx (float x1) (float y1);
        Cairo.line_to ctx (float x2) (float y2);
        Cairo.close_path ctx;
        Cairo.stroke ctx;
       ),
       (fun () ->
         let b = Buffer.create 10000 in
         Cairo_png.surface_write_to_stream surface (Buffer.add_string b);
         Buffer.contents b
       ))
    in
    let _ = Lwt_stream.iter draw_server (Eliom_bus.stream bus) in
    (bus, image_string)

let grafitti_info = Hashtbl.create 0

let imageservice = Eliom_registration.String.register_service
  ~path:["image"]
  ~headers:Http_headers.dyn_headers
  ~get_params:Eliom_parameter.(string "name" ** int "ver")
  (* We add an int parameter for the browser not to cache the image *)
  (fun (name,_) () ->
    try_lwt
      let _,image_string = Hashtbl.find grafitti_info name in
      Lwt.return (image_string (), "image/png")
    with Not_found -> raise_lwt Eliom_common.Eliom_404)

let get_bus (name : string) =
  (* Create a new bus and image_string function only if it did not exist *)
  try
    fst (Hashtbl.find grafitti_info name)
  with Not_found ->
    let bus,image_string = launch_server_canvas () in
    Hashtbl.add grafitti_info name (bus,image_string);
    bus

let main_service = Eliom_service.service
  ~path:[""]
  ~get_params:Eliom_parameter.unit ()

let multigrafitti_service = Eliom_service.service
  ~path:[""]
  ~get_params:Eliom_parameter.(suffix (string "name")) ()

let choose_drawing_from () =
  get_form ~service:multigrafitti_service
    (fun (name) ->
      [fieldset
          [label ~a:[a_for name] [pcdata "Drawing name: "];
           string_input ~input_type:`Text ~name ();
           br ();
           string_input ~input_type:`Submit ~value:"Go" ()]])


let make_static_uri xs = make_uri (Eliom_service.static_dir ()) xs

let oclosure_script = Html5.Id.create_global_elt
  (js_script ~uri:(make_static_uri ["grafitti_oclosure.js"]) ())

let make_page content =
  Lwt.return
    (html
       (head
          (title (pcdata "Grafitti"))
          [css_link ~uri:(make_static_uri ["css";"common.css"]) ();
           css_link ~uri:(make_static_uri ["css";"hsvpalette.css"]) ();
           css_link ~uri:(make_static_uri ["css";"slider.css"]) ();
           oclosure_script;
           css_link ~uri:(make_static_uri ["css";"grafitti.css"]) ();])
       (body content))


let connection_service =
  Eliom_service.post_coservice' ~post_params:
    (let open Eliom_parameter in
     (string "name" ** string "password")) ()
let disconnection_service = Eliom_service.post_coservice'
  ~post_params:Eliom_parameter.unit ()

let create_account_service =
  Eliom_service.post_coservice ~fallback:main_service ~post_params:
    (let open Eliom_parameter in (string "name" ** string "password")) ()

let username = Eliom_reference.eref
  ~scope:Eliom_common.default_session_scope None

let users = ref ["user","password";"test","test"]

let check_pwd name pwd =
   try Lwt.return (List.assoc name !users = pwd) with
   | Not_found -> Lwt.return false

let () = Eliom_registration.Action.register
  ~service:create_account_service
  (fun () (name, pwd) ->
    users := (name, pwd)::!users;
    Lwt.return ())

let () = Eliom_registration.Action.register
  ~service:connection_service
  (fun () (name, password) ->
    match_lwt check_pwd name password with
    | true -> Eliom_reference.set username (Some name)
    | false -> Lwt.return ())

let () =
  Eliom_registration.Action.register
    ~service:disconnection_service
    (fun () () -> Eliom_state.discard
      ~scope:Eliom_common.default_session_scope ())

let disconnect_box () =
  post_form disconnection_service
    (fun _ -> [fieldset
                  [string_input ~input_type:`Submit ~value:"Log out" ()]]) ()

let login_name_form service button_text =
  post_form ~service
    (fun (name1, name2) ->
      [fieldset
          [label ~a:[a_for name1] [pcdata "login: "];
           string_input ~input_type:`Text ~name:name1 ();
           br ();
           label ~a:[a_for name2] [pcdata "password: "];
           string_input ~input_type:`Password ~name:name2 ();
           br ();
           string_input ~input_type:`Submit ~value:button_text ()
          ]]) ()


let default_content () =
  make_page
    [h1 [pcdata "Welcome to Multigraffiti"];
     h2 [pcdata "log in"];
     login_name_form connection_service "Connect";
     h2 [pcdata "create account"];
     login_name_form create_account_service "Create account";]

module Connected_translate =
struct
  type page = string -> Grafitti_app.page Lwt.t
  let translate page =
    match_lwt Eliom_reference.get username with
    | None -> default_content ()
    | Some username -> page username
end

module Connected =
  Eliom_registration.Customize (Grafitti_app) (Connected_translate)

let () = Connected.register
  ~service:main_service
  (fun () () ->
    Lwt.return (fun username ->
      make_page [h1 [pcdata ("Welcome to Multigrafitti " ^ username)];
                 choose_drawing_from ()]))


