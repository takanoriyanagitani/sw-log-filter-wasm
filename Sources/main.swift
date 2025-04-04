import struct Foundation.Data
import class Foundation.ProcessInfo
import func WAT.wat2wasm
import class WasmKit.Engine
import struct WasmKit.Exports
import struct WasmKit.Function
import struct WasmKit.Instance
import struct WasmKit.Memory
import struct WasmKit.Module
import class WasmKit.Store
import enum WasmKit.Value
import func WasmKit.parseWasm
import struct WasmParser.CustomSection
import protocol WasmTypes.GuestMemory

public enum LogFilterWasmErr: Error {
  case invalidArgument(String)

  case unimplemented(String)
}

public typealias IO<T> = () -> Result<T, Error>

public func Bind<T, U>(
  _ io: @escaping IO<T>,
  _ mapper: @escaping (T) -> IO<U>
) -> IO<U> {
  return {
    let rt: Result<T, _> = io()
    return rt.flatMap {
      let t: T = $0
      return mapper(t)()
    }
  }
}

public func Lift<T, U>(
  _ pure: @escaping (T) -> Result<U, Error>
) -> (T) -> IO<U> {
  return {
    let t: T = $0
    return {
      return pure(t)
    }
  }
}

public func envValByKey(_ key: String) -> IO<String> {
  return {
    let values: [String: String] = ProcessInfo.processInfo.environment
    let oval: String? = values[key]
    guard let val = oval else {
      return .failure(
        LogFilterWasmErr
          .invalidArgument("no such env var: \( key )"))
    }
    return .success(val)
  }
}

public func filename2string(_ filename: String) -> IO<String> {
  return {
    Result(catching: { try String(contentsOfFile: filename) })
  }
}

public func watFilename() -> IO<String> { envValByKey("ENV_WAT_FILENAME") }

public func watContent() -> IO<String> { Bind(watFilename(), filename2string) }

public func parseWat(_ wat: String) -> Result<[UInt8], Error> {
  Result(catching: { try wat2wasm(wat) })
}

public func wasmBytes() -> IO<[UInt8]> { Bind(watContent(), Lift(parseWat)) }

public func bytes2module(_ bytes: [UInt8]) -> Result<Module, Error> {
  Result(catching: { try parseWasm(bytes: bytes) })
}

public func wmodule() -> IO<Module> { Bind(wasmBytes(), Lift(bytes2module)) }

public func engine2store(_ engine: Engine) -> Store {
  Store(engine: engine)
}

public typealias StoreToInstance = (Store) -> Result<Instance, Error>

public func module2store2instance(_ mdl: Module) -> StoreToInstance {
  return {
    let s: Store = $0
    return Result(catching: { try mdl.instantiate(store: s, imports: [:]) })
  }
}

public func s2instance() -> IO<StoreToInstance> {
  Bind(
    wmodule(),
    Lift {
      let mdl: Module = $0
      return .success(module2store2instance(mdl))
    }
  )
}

public typealias FuncNameToFunc = (String) -> Result<Function, Error>

public func instance2name2func(_ instance: Instance) -> FuncNameToFunc {
  return {
    let fname: String = $0
    let of: Function? = instance.exports[function: fname]
    guard let f = of else {
      return .failure(
        LogFilterWasmErr.invalidArgument(
          "no such func: \( fname )"
        ))
    }
    return .success(f)
  }
}

public typealias FunctionName = String

public struct LogFilterWasmConfigSimpleByte {
  public let fname2fn: FuncNameToFunc

  public let keep1: FunctionName
  public let setchar: FunctionName

  public init(
    _ fname2fn: @escaping FuncNameToFunc,
    keep1: FunctionName = "keep_log",
    setchar: FunctionName = "set_char"
  ) {
    self.fname2fn = fname2fn
    self.keep1 = keep1
    self.setchar = setchar
  }

  public func toLogFilter() -> Result<LogFilterWasmSimpleByte, Error> {
    let rkeeper: Result<Function, _> = self.fname2fn(self.keep1)
    let rschar: Result<Function, _> = self.fname2fn(self.setchar)
    return Result(catching: {
      let keeper: Function = try rkeeper.get()
      let schar: Function = try rschar.get()
      return LogFilterWasmSimpleByte(keepLog: keeper, setChar: schar)
    })
  }
}

public class LogFilterWasmSimpleByte {
  public let keepLog: Function
  public let setChar: Function

  public init(keepLog: Function, setChar: Function) {
    self.keepLog = keepLog
    self.setChar = setChar
  }

  public func shouldKeepLog() -> Result<Bool, Error> {
    let rval: Result<Value, _> = Result(catching: { try self.keepLog([]) })
      .flatMap {
        let values: [Value] = $0
        guard 1 == values.count else {
          return .failure(
            LogFilterWasmErr
              .invalidArgument("invalid result got: \( values )"))
        }
        return .success(values[0])
      }
    let ri: Result<Int32, _> = rval.flatMap {
      let val: Value = $0
      switch val {
      case .i32(let i): return .success(Int32(i))
      default:
        return .failure(
          LogFilterWasmErr
            .invalidArgument("unexpected type got: \( val )"))
      }
    }
    return ri.map {
      let i: Int32 = $0
      // 0 -> skip
      // 1 -> keep
      return 0 != i  // not skip = keep
    }
  }

  public func setChar(value: UInt8) -> Result<(), Error> {
    Result(catching: {
      try self.setChar([
        .i32(0),
        .i32(UInt32(value)),
      ])
    })
    .map {
      _ = $0
      return ()
    }
  }

  public func toFirstByteKeeper() -> FirstByteKeeper {
    return {
      let fbyte: UInt8 = $0
      let rkeep: Result<Bool, _> = Result(catching: {
        try self.setChar(value: fbyte).get()
        let keep: Bool = try self.shouldKeepLog().get()
        return keep
      })
      switch rkeep {
      case .success(let keep): return keep
      case .failure(let err):
        print("UNABLE TO CHECK: \( err )")
        return true
      }
    }
  }

  public func toLineKeeper() -> LineKeeper {
    fbkeeper2lkp(self.toFirstByteKeeper())
  }
}

public func data2memory(memory: Memory, offset: UInt, data: Data) {
  memory.withUnsafeMutableBufferPointer(
    offset: offset,
    count: data.count,
    {
      let ptr: UnsafeMutableRawBufferPointer = $0
      ptr.copyBytes(from: data)
    }
  )
}

public func byte2memory(memory: Memory, offset: UInt, value: UInt8) {
  memory.withUnsafeMutableBufferPointer(
    offset: offset,
    count: 1,
    {
      let ptr: UnsafeMutableRawBufferPointer = $0
      ptr.storeBytes(of: value, toByteOffset: Int(offset), as: UInt8.self)
    }
  )
}

public struct WasmInstance {
  public let instance: Instance

  public func copyData(
    offset: UInt,
    data: Data,
    _ memname: String = "memory"
  ) -> Result<(), Error> {
    let exports: Exports = self.instance.exports
    let omem: Memory? = exports[memory: "memory"]
    guard let mem = omem else {
      return .failure(
        LogFilterWasmErr
          .invalidArgument("no such memory: \( memname )"))
    }
    data2memory(memory: mem, offset: offset, data: data)
    return .success(())
  }

  public func setByte(
    offset: UInt,
    value: UInt8,
    _ memname: String = "memory"
  ) -> Result<(), Error> {
    let exports: Exports = self.instance.exports
    let omem: Memory? = exports[memory: "memory"]
    guard let mem = omem else {
      return .failure(
        LogFilterWasmErr
          .invalidArgument("no such memory: \( memname )"))
    }
    byte2memory(memory: mem, offset: offset, value: value)
    return .success(())
  }

}

public typealias Line = String
public let Keep = true
public let Skip = false

public typealias LineKeeper = (Line) -> Bool

public typealias FirstByteKeeper = (UInt8) -> Bool

public func fbkeeper2lkp(_ fbkeeper: @escaping FirstByteKeeper) -> LineKeeper {
  return {
    let line: String = $0
    let obyte: UInt8? = line.utf8.first
    return obyte.map {
      let b1st: UInt8 = $0
      return fbkeeper(b1st)
    } ?? Skip
  }
}

public typealias Lines = () -> String?

public func stdin2lines() -> Lines {
  return {
    let oline: String? = readLine()
    return oline
  }
}

public typealias LineWriter = (String) -> IO<Void>

public func line2stdout() -> LineWriter {
  return {
    let line: String = $0
    return {
      print(line)
      return .success(())
    }
  }
}

public struct LinesToFiltered {
  public let lines: Lines
  public let writer: LineWriter
  public let filter: LineKeeper

  public init(
    _ filter: @escaping LineKeeper,
    lines: @escaping Lines = stdin2lines(),
    writer: @escaping LineWriter = line2stdout()
  ) {
    self.lines = lines
    self.writer = writer
    self.filter = filter
  }

  public func lines2filtered2writer() -> IO<Void> {
    return {
      while true {
        let oline: String? = self.lines()
        guard let line = oline else {
          return .success(())
        }

        let keep: Bool = filter(line)
        guard Keep == keep else {
          continue
        }

        let wrote: Result<_, _> = self.writer(line)()
        if case let .failure(err) = wrote {
          return .failure(err)
        }
      }
    }
  }
}

@main
struct LogFilterWasm {
  static func main() {
    let is2i: IO<StoreToInstance> = s2instance()
    let eg: Engine = Engine()
    let st: Store = engine2store(eg)
    let ii: IO<Instance> = Bind(
      is2i,
      Lift {
        let s2i: StoreToInstance = $0
        return s2i(st)
      }
    )
    let in2f: IO<FuncNameToFunc> = Bind(
      ii,
      Lift {
        let instance: Instance = $0
        return .success(instance2name2func(instance))
      }
    )
    let ifilter1stcfg: IO<LogFilterWasmConfigSimpleByte> = Bind(
      in2f,
      Lift {
        let n2f: FuncNameToFunc = $0
        return .success(LogFilterWasmConfigSimpleByte(n2f))
      }
    )
    let ifilter1stByte: IO<LogFilterWasmSimpleByte> = Bind(
      ifilter1stcfg,
      Lift {
        let cfg: LogFilterWasmConfigSimpleByte = $0
        return cfg.toLogFilter()
      }
    )
    let ilkeeper: IO<LineKeeper> = Bind(
      ifilter1stByte,
      Lift {
        let lfilter: LogFilterWasmSimpleByte = $0
        return .success(lfilter.toLineKeeper())
      }
    )
    let il2filter: IO<LinesToFiltered> = Bind(
      ilkeeper,
      Lift {
        let keeper: LineKeeper = $0
        return .success(LinesToFiltered(keeper))
      }
    )

    let lines2filtered2stdout: IO<Void> = Bind(
      il2filter,
      {
        let l2f: LinesToFiltered = $0
        return l2f.lines2filtered2writer()
      }
    )

    let res: Result<_, _> = lines2filtered2stdout()
    do {
      try res.get()
    } catch {
      print("\( error )")
    }
  }
}
