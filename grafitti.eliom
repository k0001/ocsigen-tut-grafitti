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

let bus = Eliom_bus.create Json.t<messages>

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



