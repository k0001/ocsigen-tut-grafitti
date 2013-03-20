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
    draw ctx ("#ffaa33", 12, (10, 10), (200, 100))
}}

let page =
  (html
     (head (title (pcdata "Graffiti")) [])
     (body [h1 [pcdata "Graffiti"];
            canvas_elt] ) )

let main_service =
  Grafitti_app.register_service ~path:[""] ~get_params:Eliom_parameter.unit
    (fun () () ->
      (* Cf. the box "Client side side-effects on the server" *)
      ignore {unit{ init_client () }};
      Lwt.return page)
