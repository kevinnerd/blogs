---
title: Spring中观察者模式的应用
date: 2021-08-10 17:30:07
tags:
- 设计模式
- Java
- Spring
categories:
- Java
- Spring
---

## 概述

**观察者模式(Observer Pattern)** ，有时也称作 **发布-订阅模式(Publish-Subscribe Pattern)** 是工程中比较常见的一种面向对象设计模式，这种模式通常被用于解耦一些联系紧密，但又具备不同职责的对象，通过这种模式来使多个合作的对象之间达到一种一致的状态，而对象本身的代码逻辑又能独立维护，我们通常所说的**事件监听**其实就是这种模式的应用。

在本篇文章中，我通过分析Spring中的几个关于事件发布订阅的核心API以及代码实现，来讲解这种设计模式在实际项目中如何使用。同时也加深一下自己对于Spring容器中消息分发机制的理解。

## 观察者模式简介

在经典的设计模式书籍《Design Patterns-GOF》中，关于观察者模式有如下的描述：

> Define a one-to-many dependency between objects so that when one object changes state, all its dependents are notified and updated automatically.

通过上面的描述其实不难理解，所谓观察者模式，本质上就是多个对象同时观察(或者说监听)某个对象的状态变化，从而自动的做出相应的处理，其实在实际的业务场景中这种情况很常见，例如当我们在淘宝上下了一个订单，那么当这个订单状态由待支付变为已支付时，这就相当于订单的状态发生了改变，从而淘宝后台的很多系统，例如物流，库存等等，都需要根据这个状态而进行对应的处理，这其实就可以通过观察者模式来解决多个系统之间的耦合问题，当然多个不同系统之间的解耦肯定要比对象之间的解耦复杂的多，但本质的思想是一样的。

在最简单的观察者模式实现中，通常要有两个关键的对象：Subject, Observer。 其中Subject就是被观察的对象，而Observer就是观察者，下面我们来看一下这种最简单的观察者模式的类图：

![Observer Simple](/images/20210810/Observer_simple.png)

从上面的类图可以看到，Subject对象中维护着所有的Observer，并且当Subject对象状态发生改变时，通过Notify()方法通知到所有的Observer执行Update()方法；而每个ConcreteObserver对象都持有着对应的ConcreteSubject对象的引用，从而可以通过GetState()获取到Subject的最新状态。

上面介绍的是观察者模式最简单的一种实现方案，适用于简单场景，由Subject来负责同步状态给所有的Observer，通常可以通过模板方法模式实现Notify()的通知逻辑，具体的Subject对象可以直接调用上层模板的Notify()来触发状态通知。但对于复杂场景，例如Spring框架中，往往有多个Subject可以触发事件，也有多个Observer监听这些事件，这时维护Subject和Observer对象的对应关系就变得复杂了，因此常见的观察者实现都会在Subject和Observer之间增加一个角色：ChangeManager，这个角色负责实现Notify()方法中的事件通知逻辑，以及Observer对象的维护工作，对应的类图如下：

![Observer Complex](/images/20210810/Observer_complex.png)

从上图中可以看到，Notify()的实现和Subject、Observer的关系维护职责都被分离到了ChangeManager对象中。

## Spring容器中的观察者模式

上面简单说了一下观察者模式的两种实现方式，这里通过分析Spring源码，看一下Spring中观察者模式的实现，Spring中观察者模式的实现符合我们上面说的第二种实现方案，虽然命名方式上和上面有差别，但对象之间的交互和结构是基本一致的，唯一的差别就是Subject的状态变化，在Spring中包装成了事件对象，通过事件对象来传递Subject的状态变化，Observer通过接收事件对象做相应的处理，其实就是一个事件监听模式，通过事件可以让Subject和Observer达到完全的解耦，互相感知不到对方的存在。

下面我们从顶层接口分析一下Spring中观察者模式的组成部分。

### ApplicationEventPublisher

首先是`ApplicationEventPublisher`这个顶层接口，该接口中定义了下面的方法：

```java
void publishEvent(ApplicationEvent event);
```

这个其实就是上面提到的Notify()方法，通过将Event对象传递给观察者，从而同步Subject和Observer之间的状态。

其实Spring的核心容器接口`ApplicationContext`就继承了这个接口，因为在容器初始化以及运行过程中，Spring容器的状态会不断的发生变化，产生事件，因此就需要同步这些状态给Spring的各个组件以及用户自己基于Spring的扩展点实现的观察者对象，我们可以看一下下面的继承结构：

![ApplicationEventPublisher](/images/20210810/ApplicationEventPublisher.png)

### ApplicationListener

Spring的观察者其实就是`ApplicationListener`，这个接口中定义了一个方法`void onApplicationEvent(E event)`用于接收处理`ApplicationEvent`对象，这个方法其实就对应Observer中的Update方法，注意这里使用了泛型，这个泛型`E`在接口定义中是`E extends ApplicationEvent`。在Spring中有大量的基于这个接口的实现类，同时类似kafka这种中间件在集成到Spring时也会根据自己的需要实现这个接口，通常`Listener`本身的实现是多种多样的，需要根据具体的业务场景来看，所以这里就不多做解释了。

### ApplicationEventMulticaster

`ApplicationEventMulticaster`这个接口所扮演的角色其实就是上面提到的`ChangeManager`，`ApplicationEventPublisher`的具体实现会将发布事件的逻辑代理给这个对象，同时这个对象也会维护所有的`ApplicationListener`对象，并负责将事件分发给这些观察者，这个接口里定义了如下核心方法：

```java
void addApplicationListener(ApplicationListener<?> listener);
void removeApplicationListener(ApplicationListener<?> listener);
void multicastEvent(ApplicationEvent event);
```

你看，这里不是刚好和`ChangeManager`所做的事情一致吗，维护所有的观察者列表，负责发布事件给所有的观察者。

下面我们再看一下`ApplicationEventPublisher`发布事件的具体实现：

```java
protected void publishEvent(Object event, @Nullable ResolvableType eventType) {
  Assert.notNull(event, "Event must not be null");

  // Decorate event as an ApplicationEvent if necessary
  ApplicationEvent applicationEvent;
  if (event instanceof ApplicationEvent) {
    applicationEvent = (ApplicationEvent) event;
  }
  else {
    applicationEvent = new PayloadApplicationEvent<>(this, event);
    if (eventType == null) {
      eventType = ((PayloadApplicationEvent<?>) applicationEvent).getResolvableType();
    }
  }

  // Multicast right now if possible - or lazily once the multicaster is initialized
  if (this.earlyApplicationEvents != null) {
    this.earlyApplicationEvents.add(applicationEvent);
  }
  else {
    getApplicationEventMulticaster().multicastEvent(applicationEvent, eventType);
  }

  // Publish event via parent context as well...
  if (this.parent != null) {
    if (this.parent instanceof AbstractApplicationContext) {
      ((AbstractApplicationContext) this.parent).publishEvent(event, eventType);
    }
    else {
      this.parent.publishEvent(event);
    }
  }
}
```

这里的方法比较长，但我们可以看到关键的一行代码：

```java
getApplicationEventMulticaster().multicastEvent(applicationEvent, eventType);
```

你看，这里不就是上面介绍观察者模式实现时类图中所画的吗：Subject对象的notify实现会代理给`ChangeManager`对象，这里Spring也将发布事件的逻辑最终代理给了`ApplicationEventMulticaster.multicastEvent()`方法，这个方法在Spring中的实现其实也很简单，如下：

```java
	@Override
	public void multicastEvent(final ApplicationEvent event, @Nullable ResolvableType eventType) {
		ResolvableType type = (eventType != null ? eventType : resolveDefaultEventType(event));
		Executor executor = getTaskExecutor();
		for (ApplicationListener<?> listener : getApplicationListeners(event, type)) {
			if (executor != null) {
				executor.execute(() -> invokeListener(listener, event));
			}
			else {
				invokeListener(listener, event);
			}
		}
	}
```

可以看到，这里如果配置了线程池对象，那么就会并发的传递事件给所有`ApplicationListener`，否则就挨个调用`listener.onApplicationEvent()`方法。

## 总结

最后做一个简单的总结，我们通过类图的方式讲解了观察者模式所包含的一些关键对象以及它们之间的结构，同时也给出了两种常见的实现方案，同时第二种实现方案也是Spring中所使用的方案，在实际应用中，如果说我们需要实现一个观察者模式，可以通过Spring提供的Aware扩展，依托于上面讲到的Spring自己的观察者框架实现，也可以仿照Spring的模式自己实现，实现起来是非常简单的。

下面说一下什么情况下适合应用观察者模式，这里参考《Design Patterns》书中的建议，做一个简单的翻译：

1. 如果你要实现的一个抽象概念有两个部分，这两个部分互相依赖但又想独立维护，那么通过观察者模式可以让你很好的将两部分解耦
2. 当一个对象的状态变化需要引起其他关联对象也随之变化，同时你又不确定受影响的对象有哪些的时候，可以应用观察者模式解决
3. 当一个对象需要发出通知消息给其他对象，但又不关心哪些对象想要接收这个通知，这时可以通过观察者模式解耦消息的发送者和接收者