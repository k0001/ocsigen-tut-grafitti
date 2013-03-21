{shared{
  (* Modules open in the shared-section are available in client- and
     server-code! *)
  open Eliom_content.Html5.D
  open Lwt
}}

open Eliom_content.Html5.D (* provides functions to create HTML nodes *)


module Grafitti_app =
  Eliom_registration.App (struct
    let application_name = "grafitti"
  end)

{shared{
  let width = 700
  let height = 400
}}

let canvas_elt =
  canvas ~a:[a_width width; a_height height]
    [pcdata "your browser doesn't support canvas"]

{shared{
  type messages = (string * int * (int * int) * (int * int))
    deriving (Json)
}}

let rgb_from_string color = (* color is in format #rrggbb *)
  let get_color i =
    float_of_string ("0x"^(String.sub color (1+2*i) 2)) /. 255. in
  try get_color 0, get_color 1, get_color 2 with | _ -> 0., 0., 0.

let draw_server, image_string =
  let surface =
    Cairo.image_surface_create Cairo.FORMAT_ARGB32 ~width ~height in
  let ctx = Cairo.create surface in
  ((fun ((color : string), size, (x1, y1), (x2, y2)) ->
    Cairo.set_line_width ctx (float size) ;
    Cairo.set_line_join ctx Cairo.LINE_JOIN_ROUND ;
    Cairo.set_line_cap ctx Cairo.LINE_CAP_ROUND ;
    let red, green, blue = rgb_from_string color in
    Cairo.set_source_rgb ctx ~red ~green ~blue ;
    Cairo.move_to ctx (float x1) (float x2) ;
    Cairo.line_to ctx (float x1) (float x2) ;
    Cairo.close_path ctx ;
    Cairo.stroke ctx ;
   ),
   (fun () ->
     let b = Buffer.create 10000 in
     (* Output a PNG in a string *)
     Cairo_png.surface_write_to_stream surface (Buffer.add_string b);
     Buffer.contents b
   ))

let bus = Eliom_bus.create Json.t<messages>

let _ = Lwt_stream.iter draw_server (Eliom_bus.stream bus)

let imageservice =
  Eliom_registration.String.register_service
    ~path:["image"]
    ~get_params:Eliom_parameter.unit
    (fun () () -> Lwt.return (image_string (), "image/png"))


{client{
  let draw ctx (color, size, (x1, y1), (x2, y2)) =
    ctx##strokeStyle <- (Js.string color);
    ctx##lineWidth <- float size;
    ctx##beginPath();
    ctx##moveTo(float x1, float y1);
    ctx##lineTo(float x2, float y2);
    ctx##stroke()

       let init_client () =
         let canvas = Eliom_content.Html5.To_dom.of_canvas %canvas_elt in
         let ctx = canvas##getContext (Dom_html._2d_) in
         ctx##lineCap <- Js.string "round";

         (* The initial image: *)
         let img = Eliom_content.Html5.To_dom.of_img
           (img ~alt:"canvas" ~src:(make_uri ~service:%imageservice ()) ()) in
         img##onload <- Dom_html.handler
           (fun ev -> ctx##drawImage(img, 0., 0.); Js._false);

         (* Size of the brush *)
         let slider = jsnew Goog.Ui.slider(Js.null) in
         slider##setMinimum(1.);
         slider##setMaximum(80.);
         slider##setValue(10.);
         slider##setMoveToPointEnabled(Js._true);
         slider##render(Js.some Dom_html.document##body);
         (* The color palette: *)
         let pSmall =
           jsnew Goog.Ui.hsvPalette(Js.null, Js.null,
                                    Js.some (Js.string "goog-hsv-palette-sm"))
         in
         pSmall##render(Js.some Dom_html.document##body);

         let x = ref 0 and y = ref 0 in

         let set_coord ev =
           let x0, y0 = Dom_html.elementClientPosition canvas in
           x := ev##clientX - x0; y := ev##clientY - y0
         in

         let compute_line ev =
           let oldx = !x and oldy = !y in
           set_coord ev;
           let color = Js.to_string (pSmall##getColor()) in
           let size = int_of_float (Js.to_float (slider##getValue())) in
           (color, size, (oldx, oldy), (!x, !y))
         in

         let line ev =
           let v = compute_line ev in
           let _ = Eliom_bus.write %bus v in
           draw ctx v;
           Lwt.return () in

         Lwt.async
           (fun () ->
        let open Lwt_js_events in
        mousedowns canvas
          (fun ev _ ->
            set_coord ev; line ev >>= fun () ->
            Lwt.pick [mousemoves Dom_html.document (fun x _ -> line x);
                      mouseup Dom_html.document >>= line]));

   Lwt.async (fun () -> Lwt_stream.iter (draw ctx) (Eliom_bus.stream %bus))
}}




let page =
  html
    (Eliom_tools.F.head ~title:"Grafitti"
       ~css:[
         ["css";"common.css"];
         ["css";"hsvpalette.css"];
         ["css";"slider.css"];
         ["css";"grafitti.css"];
         ["grafitti_oclosure.js"];
       ]
       ~js:[ ["grafitti_oclosure.js"] ] ())
    (body [h1 [pcdata "Grafitti"]; canvas_elt])

let main_service =
  Grafitti_app.register_service ~path:[""] ~get_params:Eliom_parameter.unit
    (fun () () ->
      (* Cf. the box "Client side side-effects on the server" *)
      ignore {unit{ init_client () }};
      Lwt.return page)



