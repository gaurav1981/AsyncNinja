//
//  Copyright (c) 2016-2017 Anton Mironov
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"),
//  to deal in the Software without restriction, including without limitation
//  the rights to use, copy, modify, merge, publish, distribute, sublicense,
//  and/or sell copies of the Software, and to permit persons to whom
//  the Software is furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL
//  THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
//  IN THE SOFTWARE.
//

#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
  import Foundation

  // MARK: - regular observation
  
  public extension Retainer where Self: NSObject {
    /// makes an UpdatableProperty for specified key path
    ///
    /// - Parameter keyPath: to observe
    /// - Parameter executor: apply changes on
    /// - Parameter observationSession: is an object that helps to control observation
    /// - Parameter channelBufferSize: size of the buffer within returned channel
    /// - Returns: channel new values
    func updatable<T>(
      for keyPath: String,
      executor: Executor,
      observationSession: ObservationSession? = nil,
      channelBufferSize: Int = 1
      ) -> UpdatableProperty<T?> {
      let producer = UpdatableProperty<T?>(bufferSize: channelBufferSize, updateExecutor: executor) { [weak self] (producerProxy, event) in
        switch event {
        case let .update(update):
          self?.setValue(update, forKey: keyPath)
        case .completion:
          nop()
        }
      }
      
      let observer = KeyPathObserver(object: self, keyPath: keyPath, options: [.initial, .old, .new], enabled: observationSession?.enabled ?? true) {
        [weak producer] (changes) in
        producer?.updateWithoutHandling(changes[.newKey] as? T)
      }
      
      observationSession?.observers.push(observer)
      notifyDeinit { [weak producer] in
        producer?.cancelBecauseOfDeallocatedContext()
        observer.enabled = false
      }
      
      return producer
    }
    
    /// makes an UpdatableProperty for specified key path
    ///
    /// - Parameter keyPath: to observe
    /// - Parameter executor: apply changes on
    /// - Parameter observationSession: is an object that helps to control observation
    /// - Parameter placeholder: placeholder for nil value
    /// - Parameter channelBufferSize: size of the buffer within returned channel
    /// - Returns: channel new values
    func updatable<T>(
      for keyPath: String,
      executor: Executor,
      observationSession: ObservationSession? = nil,
      onNone: UpdateWithNoneHandlingPolicy<T>,
      channelBufferSize: Int = 1
      ) -> UpdatableProperty<T> {
      let producer = UpdatableProperty<T>(bufferSize: channelBufferSize, updateExecutor: executor) { [weak self] (producerProxy, event) in
        switch event {
        case let .update(update):
          self?.setValue(update, forKey: keyPath)
        case .completion:
          nop()
        }
      }
      
      let observer = KeyPathObserver(object: self, keyPath: keyPath, options: [.initial, .old, .new], enabled: observationSession?.enabled ?? true) {
        [weak producer] (changes) in
        if let update = changes[.newKey] as? T {
          producer?.updateWithoutHandling(update)
        } else if case let .replace(update) = onNone {
          producer?.updateWithoutHandling(update)
        }
      }
      
      observationSession?.observers.push(observer)
      notifyDeinit { [weak producer] in
        producer?.cancelBecauseOfDeallocatedContext()
        observer.enabled = false
      }
      
      return producer
    }

    /// makes channel of changes of value for specified key path
    ///
    /// - Parameter keyPath: to observe
    /// - Parameter observationSession: is an object that helps to control observation
    /// - Parameter channelBufferSize: size of the buffer within returned channel
    /// - Returns: channel of pairs (old, new) values
    func updating<T>(
      for keyPath: String,
      observationSession: ObservationSession? = nil,
      channelBufferSize: Int = 1
      ) -> Updating<T?> {
      return updatingChanges(for: keyPath, options: [.initial, .old, .new], observationSession: observationSession, channelBufferSize: channelBufferSize)
        .map(executor: .immediate) { $0[.newKey] as? T }
    }

    /// makes channel of changes of value for specified key path
    ///
    /// - Parameter keyPath: to observe
    /// - Parameter observationSession: is an object that helps to control observation
    /// - Parameter channelBufferSize: size of the buffer within returned channel
    /// - Returns: channel of pairs (old, new) values
    func updating<T>(
      for keyPath: String,
      observationSession: ObservationSession? = nil,
      onNone: UpdateWithNoneHandlingPolicy<T>,
      channelBufferSize: Int = 1
      ) -> Updating<T> {
      return updatingChanges(for: keyPath, options: [.initial, .old, .new], observationSession: observationSession, channelBufferSize: channelBufferSize)
        .flatMap(executor: .immediate) { (changes) -> T? in
          if let update = changes[.newKey] as? T {
            return update
          } else if case let .replace(update) = onNone {
            return update
          } else {
            return nil
          }
      }
    }

    /// makes channel of changes of value for specified key path
    ///
    /// - Parameter keyPath: to observe
    /// - Parameter observationSession: is an object that helps to control observation
    /// - Parameter channelBufferSize: size of the buffer within returned channel
    /// - Returns: channel of pairs (old, new) values
    func updatingOldAndNew<T>(
      of keyPath: String,
      observationSession: ObservationSession? = nil,
      channelBufferSize: Int = 1
      ) -> Updating<(old: T?, new: T?)> {
      return updatingChanges(for: keyPath, options: [.initial, .old, .new], observationSession: observationSession, channelBufferSize: channelBufferSize)
        .map(executor: .immediate) { (old: $0[.oldKey] as? T, new: $0[.newKey] as? T) }
    }

    /// makes channel of changes of value for specified key path
    ///
    /// - Parameter keyPath: to observe
    /// - Parameter observationSession: is an object that helps to control observation
    /// - Parameter channelBufferSize: size of the buffer within returned channel
    /// - Returns: channel of changes dictionaries (see Foundation KVO for details)
    func updatingChanges(
      for keyPath: String,
      options: NSKeyValueObservingOptions,
      observationSession: ObservationSession? = nil,
      channelBufferSize: Int = 1
      ) -> Updating<[NSKeyValueChangeKey: Any]> {
      let producer = Updatable<[NSKeyValueChangeKey: Any]>(bufferSize: channelBufferSize)

      let observer = KeyPathObserver(object: self, keyPath: keyPath, options: options, enabled: observationSession?.enabled ?? true) {
        [weak producer] (changes) in
        producer?.update(changes)
      }

      observationSession?.observers.push(observer)
      notifyDeinit { [weak producer] in
        producer?.cancelBecauseOfDeallocatedContext()
        observer.enabled = false
      }

      return producer
    }
  }

  public enum UpdateWithNoneHandlingPolicy<T> {
    case drop
    case replace(T)
  }

  public extension ExecutionContext where Self: NSObject {

    /// makes an UpdatableProperty for specified key path
    ///
    /// - Parameter keyPath: to observe
    /// - Parameter observationSession: is an object that helps to control observation
    /// - Parameter channelBufferSize: size of the buffer within returned channel
    /// - Returns: channel new values
    func updatable<T>(
      for keyPath: String,
      observationSession: ObservationSession? = nil,
      channelBufferSize: Int = 1
      ) -> UpdatableProperty<T?> {
      return updatable(for: keyPath, executor: self.executor, observationSession: observationSession, channelBufferSize: channelBufferSize)
    }

    /// makes an UpdatableProperty for specified key path
    ///
    /// - Parameter keyPath: to observe
    /// - Parameter executor: apply changes on
    /// - Parameter observationSession: is an object that helps to control observation
    /// - Parameter placeholder: placeholder for nil value
    /// - Parameter channelBufferSize: size of the buffer within returned channel
    /// - Returns: channel new values
    func updatable<T>(
      for keyPath: String,
      observationSession: ObservationSession? = nil,
      onNone: UpdateWithNoneHandlingPolicy<T>,
      channelBufferSize: Int = 1
      ) -> UpdatableProperty<T> {
      return updatable(for: keyPath, executor: self.executor, observationSession: observationSession, onNone: onNone, channelBufferSize: channelBufferSize)
    }
  }

  private class KeyPathObserver: NSObject {
    let object: Unmanaged<NSObject>
    let keyPath: String
    let options: NSKeyValueObservingOptions
    let observationBlock: ([NSKeyValueChangeKey: Any]) -> Void
    var enabled: Bool {
      didSet {
        if enabled == oldValue {
          return
        } else if enabled {
          object.takeUnretainedValue().addObserver(self, forKeyPath: keyPath, options: options, context: nil)
        } else {
          object.takeUnretainedValue().removeObserver(self, forKeyPath: keyPath)
        }
      }
    }

    init(object: NSObject, keyPath: String, options: NSKeyValueObservingOptions, enabled: Bool, observationBlock: @escaping ([NSKeyValueChangeKey: Any]) -> Void) {
      self.object = Unmanaged.passUnretained(object)
      self.keyPath = keyPath
      self.options = options
      self.observationBlock = observationBlock
      self.enabled = enabled
      super.init()
      if enabled {
        object.addObserver(self, forKeyPath: keyPath, options: options, context: nil)
      }
    }

    deinit {
      self.enabled = false
    }

    override func observeValue(forKeyPath keyPath: String?,
                               of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?,
                               context: UnsafeMutableRawPointer?) {
      assert(keyPath == self.keyPath)
      if let change = change {
        observationBlock(change)
      }
    }
  }
  

  /// An object that is able to control (enable and disable) observation-related channel constructors
  public class ObservationSession {

    /// enables or disables observation
    public var enabled: Bool {
      didSet {
        if enabled != oldValue {
          observers.forEach {
            $0.enabled = enabled
          }
        }
      }
    }

    fileprivate var observers = QueueOfWeakElements<KeyPathObserver>()

    /// designated initializer
    public init(enabled: Bool = true) {
      self.enabled = enabled
    }
  }

  public struct ReactiveProperties<Object: NSObjectProtocol> {
    var object: Object
    var observationSession: ObservationSession?

    init(object: Object, observationSession: ObservationSession?) {
      self.object = object
      self.observationSession = observationSession
    }
  }

  public extension NSObjectProtocol {
    func reactiveProperties(observationSession: ObservationSession? = nil) -> ReactiveProperties<Self> {
      return ReactiveProperties(object: self, observationSession: observationSession)
    }

    var rp: ReactiveProperties<Self> { return reactiveProperties() }
    var rx: ReactiveProperties<Self> { return reactiveProperties() }
  }
#endif