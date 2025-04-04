(module

  (memory $mem0 1)

  (func $bufsz (result i32) i32.const 65536)

  (func $setchar (param $offset i32) (param $val i32)
    local.get $offset
    local.get $val
    i32.store8
  )

  (func $keeplog (result i32)
    i32.const 0
    i32.load8_u
    i32.const 0x74 ;; 't'
    i32.eq
  )

  (export "buffer_size" (func $bufsz))
  (export "keep_log" (func $keeplog))

  (export "set_char" (func $setchar))

  (export "memory" (memory $mem0))

)
