---
title: Java线程池框架源码分析
date: 2021-07-26 15:12:46
tags: 
- Java
- 线程池
categories:
- Java
---

## 概述

说到线程池框架，相信任何一个Java开发人员都不会陌生，无论是在面试中还是实际的工作中，线程池框架都是一个合格的Java工程师需要了解的技术，但大部分的初级开发者都仅限于知道如何使用线程池，对于线程池背后的设计思想和实现细节却很少关注，因此我希望通过这篇文章能够基于自己的理解，聊一聊线程池框架。
由于很多知名的Java框架，例如Guava，Spring都有自己的线程池实现，但总体都遵循JDK的核心API，使用方式大同小异，因此我这里主要关注ThreadPoolExecutor这个JDK提供的标准线程池的实现逻辑来讲，毕竟篇幅太多可能也不利于把一件事情说明白。

## 线程池框架要解决的问题

![Executor Framework](/images/20210726/Executor.png)

其实任何一个框架或技术的出现，最初的目的一定是为了解决某个开发中的痛点或行业内的问题，因此我觉得想要理解线程池框架，那也需要先了解一下线程池框架主要解决了什么问题。为了探究这个问题的答案，我建议大家可以阅读一下线程池框架顶层Interface：`Executor` 的JavaDoc说明，这里我把关键的一句话贴在这里：

> This interface provides a way of decoupling task submission from the mechanics of how each task will be run, including details of thread use, scheduling, etc.

我这里不会去翻译这句话的整体含义，但其中有个很关键的词：**decoupling**，也就是**解耦**，同样的，在线程池框架设计者[Doug Lea](https://en.wikipedia.org/wiki/Doug_Lea)参与编写的经典书籍《Java Concurrency in Practice》中6.2小节开篇也有类似的一段话，我也贴在这里：

> Executor may be a simple interface, but it forms the basis for a flexible and powerful framework for asynchronous task execution that supports a wide vari- ety of task execution policies. It provides a standard means of decoupling task submission from task execution, describing tasks with Runnable.

其实从作者的这两断类似的表述可以看到，线程池框架的核心思想其实就是将**task submission** 和 **task execution** 解耦，让线程池的使用者只需要关注我要执行的任务如何提交给线程池执行，而具体如何去执行任务，如何去调度管理线程以及线程池的生命周期等等技术细节，都由线程池框架封装在具体实现中，这样就可以大大的提高用户的开发效率，也使得使用Java实现多线程任务变得容易的多。

其实我们完全可以对比一下，如果不用线程池框架，我们自己来编写多线程并发执行某段代码的逻辑，如何来实现？最最简单的实现可能像下面这样：

```java
new Thread(() -> {
      // business logic...
    }).start();

new Thread(() -> {
      // business logic...
    }).start();
```

这种方式完全不考虑线程的管理，只考虑如何执行自己的逻辑，由于线程资源的调度是和底层CPU的逻辑线程数相关的，因此这种无限制的创建线程不加以管理的方式肯定是不ok的；那么如果说我们用线程池框架来写这种逻辑，就变得非常简单。

```java
executor.execute(() -> {
  // business logic...
})
```

其实对于自己实现线程管理逻辑来说，无论你如何来写这段逻辑，要想多个线程执行相同的代码，又不出现并发问题，都需要很详细的设计，并且需要考虑的Corner case可能超越你的想象，同时也需要编写者对于操作系统方面的知识有一定的了解，这对于只关注自己业务逻辑的开发者来说，投入和产出比无疑是不值得的，因此这就是线程池框架的意义所在。

## ThreadPoolExecutor的核心设计

我们现在了解到线程池框架的核心目标是解耦，那么其实可以自己思考一下，在软件设计领域里，解耦的最常见的实现方案是什么？答案就是**生产者消费者模式**，其实线程池框架本质上就是一个生产者消费者模式的实现，生产者是提交任务给线程池的线程，任务对象会统一放到一个阻塞队列中等待执行，而消费者是线程池中维护的多个worker线程，这些worker线程会从阻塞队列中获取未执行的任务开始执行。

其实在很多实际的应用场景中，我们都会应用到生产者消费者模式来对某些代码进行解耦，这种模式也叫观察者模式，像我们工作中用到消息中间件的场景，有些也是为了代码解耦，分离职责。

这里再次引用《Java Concurrency in Practice》中的一段话来印证我这里的说法：

> Executor is based on the producer-consumer pattern, where activities that submit tasks are the producers (producing units of work to be done) and the threads that execute tasks are the consumers (consuming those units of work). Using an Executor is usually the easiest path to implementing a producer-consumer design in your application.

我这里简单翻译一下这段话的意思：Executor是基于生产者-消费者模式的，其中生产者负责提交任务给线程池，而执行任务的线程就是消费者，使用线程池框架通常是在应用中实现生产者-消费者模式的最简单方式。

## ThreadPoolExecutor源码分析

因为线程池代码的设计细节很多，我这里无法把所有的细节都讲清楚，因此这里会从框架使用者的角度来分析代码实现。

### 创建线程池对象

要使用线程池，那么首先需要了解创建线程池对象的核心参数，所以我们首先来了解ThreadPoolExecutor的构造方法中提供的参数有哪些，以及它们的使用场景。

```java
  public ThreadPoolExecutor(int corePoolSize,
                            int maximumPoolSize,
                            long keepAliveTime,
                            TimeUnit unit,
                            BlockingQueue<Runnable> workQueue,
                            ThreadFactory threadFactory,
                            RejectedExecutionHandler handler) {
      if (corePoolSize < 0 ||
          maximumPoolSize <= 0 ||
          maximumPoolSize < corePoolSize ||
          keepAliveTime < 0)
          throw new IllegalArgumentException();
      if (workQueue == null || threadFactory == null || handler == null)
          throw new NullPointerException();
      this.acc = System.getSecurityManager() == null ?
              null :
              AccessController.getContext();
      this.corePoolSize = corePoolSize;
      this.maximumPoolSize = maximumPoolSize;
      this.workQueue = workQueue;
      this.keepAliveTime = unit.toNanos(keepAliveTime);
      this.threadFactory = threadFactory;
      this.handler = handler;
  }
```

这里我们看一下参数最多的一个构造方法都初始化了哪些参数，其他的构造方法都是通过this调用的方式调用这个构造方法，这里我们分别讲解一下这几个参数的对应的含义和用法。

#### 控制线程数量:corePoolSize、maximumPoolSize

`corePoolSize`和`maximumPoolSize`这两个参数分别代表线程池的核心线程数量和最大线程数量，这两个参数都是创建线程池对象必须指定的参数，从上面构造方法的逻辑我们可以看到，如果用户指定的`corePoolSize`大于`maximumPoolSize`就会抛出异常，因此在设置这两个参数时，我们有两种选择：

1. `corePoolSize` == `maximumPoolSize`
2. `corePoolSize` < `maximumPoolSize`

这两种选择会导致线程池在维护Worker线程的数量时有不同的行为，下面我们举例说明一下这两种情况下线程池扩容的行为有何不同：

假设我们创建一个线程池对象，并将这两个参数初始都设置为5，那么当没有任何任务提交给线程池执行时，线程池中Worker的状态是下面这样的：

![Worker Status 01](/images/20210726/WorkerStatus_01.png)

也就是说，初始状态下，线程池是不会创建任何线程的，只有当开始接收到任务时，才会开始创建Worker线程，其实从构造方法中也可以很清楚的看到，里面并没有任何创建worker相关的代码出现。

那么当我们开始提交任务给线程池之后，线程池就会开始创建Worker线程，当Worker线程的数量小于`corePoolSize`（这里是5）时，线程池会优先创建新的Worker线程来执行这个任务，如下图：

![Worker Status 02](/images/20210726/WorkerStatus_02.png)

随着我们提交给线程池的任务越来越多，当超过了核心线程数量，并且线程池中的所有Worker线程又都处于工作状态，那么新提交的任务就会被放到一个阻塞队列中，如下图所示：

![Worker Status 03](/images/20210726/WorkerStatus_03.png)

那么这里就有一个问题，这个阻塞队列可以是无限的，也可以是有限的，如果是无限的队列，那么`maximumPoolSize`这个参数就没有任何意义了，因为永远也不会用到；但如果这个队列是有限的，那么就会出现无法提交新的任务到队列中的情况(因为队列满了嘛)，那么这时新提交的任务如何处理呢？这种情况下，线程池就会根据`maximumPoolSize`做出判断：是否可以创建新的Worker线程来完成新提交的任务，但由于我们将`maximumPoolSize`和`corePoolSize`设置的值相同，因此Worker的最大数量就是5个，这时线程池就无法处理这个任务从而将新提交的任务通过拒绝策略拒绝掉。

那么真实的ThreadPoolExecutor代码是不是真如我上面所说呢？下面我们来看一下`execute`方法的实现逻辑，以下代码实现基于JDK1.8，这里我对真实代码做了删减，只保留了我上面提到的逻辑：

```java
public void execute(Runnable command) {
    if (command == null)
        throw new NullPointerException();

    // 这里作者有一大段的注释，详细说明了这个方法的执行逻辑，如果感兴趣可以自己去找对应的源码阅读，这里我删掉了
    int c = ctl.get();
    if (workerCountOf(c) < corePoolSize) { // 如果worker数量小于corePoolSize，就调用 addWorker 增加worker线程
        if (addWorker(command, true))
            return;
        c = ctl.get();
    }
    if (isRunning(c) && workQueue.offer(command)) { // 如果worker数量大于corePoolSize，将任务提交到阻塞队列
        // recheck 逻辑 ...
    }
    else if (!addWorker(command, false)) // 如果阻塞队列无法提交新的任务，就再尝试增加worker线程，如果增加失败，就执行拒绝策略
        reject(command);
}

// 由于addWorker中代码比较复杂，我这里只把最关键的有关于maximumPoolSize的判断逻辑放在这
private boolean addWorker(Runnable firstTask, boolean core) {
    // .......上面有一堆代码........
    int wc = workerCountOf(c);
    if (wc >= CAPACITY ||
        wc >= (core ? corePoolSize : maximumPoolSize)) 
        // 这里根据core这个布尔值判断，如果为true，就判断当前worker数量是否大于corePoolSize
        // 如果为false，就判断worker数量是否大于maximumPoolSize
        // 这里可以对比上面execute方法中对于addWorker的两次调用，一次传入的是true，第二次是否false
        return false;
    // .......下面代码负责创建新的worker........
}
```

#### 空闲Worker线程的回收：keepAliveTime

这里我们来讲讲`keepAliveTime`这个参数，`TimeUnit unit`这个参数仅仅是限制了`keepAliveTime`的单位而已，所以这里不做特别说明。

在上面一节我们提到，随着任务不断的提交给线程池执行，线程池中的worker线程会根据`corePoolSize`和`maxmiumPoolSize`的值有所增加，那么在真实场景中还有另外一种情况，就是当某一段时间没有什么任务提交给线程池，那么很可能导致线程池中的Worker线程大部分处于空闲状态，其实我们可以想象一下双十一的场景，相信在双十一当天活动开始的那一刻，淘宝后台可能有很多的线程池出现满负荷的状态，于是worker线程很快就达到了maxmiumPoolSize的值（这里我们不考虑队列长度无限的情况），但随着活动结束，流量下降，这些临时拉来干活的worker线程其实就没有了存在的意义，于是就到了`keepAliveTime`参数出场的时候了。

也就是说，当worker线程一直处于不工作状态，并且达到了`keepAliveTime`指定的时间之后，那么这个worker就会从线程池的集合中移除。但这里需要注意的一点是，只有当worker的数量超过`corePoolSize`并且小于`maxmiumPoolSize`时，才会执行这个逻辑来减少worker线程，当减少到`corePoolSize`指定的值时，就不再减少了，所以说线程池中常驻线程的数量主要还是由`corePoolSize`决定的。

如果说在我们实际的使用中，想要线程池中的核心线程也遵循`keepAliveTime`的规则来动态减少，这里ThreadPoolExecutor为我们提供了一个参数`allowCoreThreadTimeOut`，这个参数的默认值为false，要修改这个参数可以调用下面的方法：

```java
public void allowCoreThreadTimeOut(boolean value); 
```

为了验证我上面所说的逻辑，带着大家看一下具体实现，这部分的实现可能有点绕，我这里分几部分来说（代码有删减，仅供参考）。

在上面的核心设计部分，我提到了线程池框架是基于生产者消费者模型实现的，Worker线程作为消费者，需要不断的从任务队列中获取任务来执行，而执行这段逻辑的核心方法就是下面的`runWorker()`:

```java
final void runWorker(Worker w) {
    Thread wt = Thread.currentThread();
    Runnable task = w.firstTask;
    // ============
    // 这里去掉了一段代码
    // ============ 
    boolean completedAbruptly = true;
    try {
        while (task != null || (task = getTask()) != null) {
            w.lock();
            // ============
            // 这里去掉了一段代码
            // ============ 
            try {
              // ============
              // 这里去掉了线程开始执行逻辑前的扩展接口调用和try catch block
              // ============ 
                task.run();
              // ============
              // 这里去掉了线程执行完成后的扩展接口调用和try catch block
              // ============ 
            } finally {
                task = null;
                w.completedTasks++;
                w.unlock();
            }
        }
        completedAbruptly = false;
    } finally {
        processWorkerExit(w, completedAbruptly);
    }
}
```

在我精简了`runWorker`中的一部分代码之后，剩下的核心处理逻辑其实很好理解，每个Worker线程在启动时都会先分配一个firstTask对象，也就是这个线程执行的第一个任务，当第一个任务执行完成之后，后续的任务就通过`getTask()`方法从队列中获取任务来执行，执行完成后，更新completedTasks的计数，直到队列中无法再获取到新的任务，于是执行finally部分的`processWorkerExit()`方法退出当前线程。

看到这你可能有个疑问，这段代码看上去并没有提到前面说的`keepAliveTime`参数啊？其实这里我们需要再深入的看一下`getTask()`和`processWorkerExit()`这两个方法的实现逻辑，并且这两个方法需要结合起来才能理解`keppAliveTime`以及前面提到的`allowCoreThreadTimeOut`这两个参数。

下面我们看一下`getTask()`的代码逻辑：

```java
private Runnable getTask() {
    boolean timedOut = false; // Did the last poll() time out?

    for (;;) {
        int c = ctl.get();
        int wc = workerCountOf(c); // 获取当前的worker数量
        // 这里去掉了一部分代码
        boolean timed = allowCoreThreadTimeOut || wc > corePoolSize;

        if ((wc > maximumPoolSize || (timed && timedOut))
            && (wc > 1 || workQueue.isEmpty())) {
            if (compareAndDecrementWorkerCount(c))
                return null;
            continue;
        }

        try {
            Runnable r = timed ?
                workQueue.poll(keepAliveTime, TimeUnit.NANOSECONDS) :
                workQueue.take();
            if (r != null)
                return r;
            timedOut = true;
        } catch (InterruptedException retry) {
            timedOut = false;
        }
    }
}
```

为了能够讲清楚这段代码的逻辑，我们对worker的数量做一个限定，假设`wc > corePoolSize && wc < maximumPoolSize`，也就是触发上面所说的线程回收逻辑的条件，另外假设`allowCoreThreadTimeOut = false`，那么上面的代码逻辑就可以简化成下面的代码：

```java
private Runnable getTask() {
    boolean timedOut = false; // Did the last poll() time out?

    for (;;) {
        int c = ctl.get();
        int wc = workerCountOf(c); // 获取当前的worker数量
        // 这里去掉了一部分代码
        boolean timed = false || true;

        if ((false || (true && timeout)) // 这里if的条件是false，因此这段逻辑不会执行
            && (wc > 1 || workQueue.isEmpty())) {
            if (compareAndDecrementWorkerCount(c))
                return null;
            continue;
        }

        try {
            Runnable r = workQueue.poll(keepAliveTime, TimeUnit.NANOSECONDS); //由于timed变量的值是true，因此这里也简化了
            if (r != null)
                return r;
            timedOut = true;
        } catch (InterruptedException retry) {
            timedOut = false;
        }
    }
}
```

通过阅读上面的代码逻辑，如果任务队列`workQueue`中没有任何任务产生，当达到`keepAliveTime`的超时时间之后（注意这里的TimeUnit是一个固定值，但我们设定参数时却可以指定单位，是因为在构造方法中对单位提前做了转换，统一转为了NANOSECONDS），那么`Runnable r`，这个变量的值就是`null`，于是`timeout`为true进入下一轮循环，在进入到下一轮循环之后，由于`timeout`变量为true导致执行if代码块的逻辑，通过cas操作先减少worker的计数值，然后方法返回`null`值结束这段逻辑。

这个方法里值得注意的点有两个：
1. 只要worker线程数量大于指定的核心线程数，或者打开了`allowCoreThreadTimeOut`设置，那么就从任务队列获取任务的方法就从`take()`变为了`poll(keepAliveTime, TimeUnit.NANOSECONDS)`，二者的区别就在于后者会因为超时返回`null`值，前者会一直阻塞直到新的任务提交。
2. 当任务获取由于超时返回空值，并且worker数量满足线程池的回收标准时（也就是第一点的情况），就会先减少worker计数，然后返回`null`值到`runWorker`方法

在了解了上面的逻辑之后，我们回到`runWorker`方法的逻辑，当`getTask()`返回`null`值时，接下来就会执行`processWorkerExit(w, false);`（注意这里的第二个参数，在正常执行逻辑的情况下一定是false，但异常中断的情况下可能会因为执行不到for循环外的那条语句而仍然为true），那么我们来看看`processWorkerExit`这个方法的逻辑：

```java
private void processWorkerExit(Worker w, boolean completedAbruptly) {
    // 这里删掉了completedAbruptly的处理逻辑，我们只考虑正常执行的情况
    final ReentrantLock mainLock = this.mainLock;
    mainLock.lock();
    try {
        completedTaskCount += w.completedTasks;
        workers.remove(w); // 这里从worker set中移除执行完任务的worker线程
    } finally {
        mainLock.unlock();
    }

    tryTerminate(); // RUNNING状态下这个方法没有任何作用

    int c = ctl.get();
    if (runStateLessThan(c, STOP)) { // 如果线程池没有被终止，即没有处于STOP的状态，正常情况下是RUNNING状态，因此这里是true
        if (!completedAbruptly) { // 这里也是 true
            int min = allowCoreThreadTimeOut ? 0 : corePoolSize;
            if (min == 0 && ! workQueue.isEmpty())
                min = 1;
            if (workerCountOf(c) >= min)  // 这里如果worker数量 >= min，就直接return，否则就会增加一个闲置的worker线程以维持线程池中的worker数量
                return; // replacement not needed
        }
        addWorker(null, false);
    }
}
```

讲到这里，我们就可以把上面从`runWorker`开始，到`getTask`，再到`processWorkerExit`整体的逻辑串起来，从而说明`keepAliveTime`如何控制worker线程的回收了。

我们还是考虑上面双十一结束之后的场景，在活动刚刚结束的时候，任务队列里堆积着大量的业务task对象等待worker线程执行，这时每个worker线程都在有条不紊的执行着`runWorker`方法，通过`getTask`获取task对象，并执行`task.run()`，而随着时间推移，任务队列里的任务越来越少，导致有些worker线程从任务队列中通过`poll(keepAliveTime, unit)`获取任务时超时了，于是这些线程进入到了`processWorkerExit`的逻辑中，在这个方法中，首先将worker线程从线程池的worker set中移除，然后检查当前的worker数量是否小于`corePoolSize`指定的核心线程数，如果小于，那么再创建一个worker线程添加到worker set中，以维持线程池中worker线程的数量永远大于等于`corePoolSize`，但这里如果用户指定了`allowCoreThreadTimeOut = true`，那么当任务队列为空时，线程池中所有的worker线程都会被回收掉。

其实从上面`getTask`的代码逻辑可以看出，如果说我们**没有**指定`allowCoreThreadTimeOut = true`，并且`corePoolSize`和`maxmiumPoolSize`的值相等，那就会导致`getTask`中的局部变量`timed`的值一直为false，从而使所有worker线程阻塞在`workQueue.take()`这行代码，导致keepAliveTime参数失去意义，这一点其实在javadoc中也有描述：

> By default, the keep-alive policy applies only when there are more than corePoolSize threads.

#### 任务阻塞队列：workQueue

在前面的内容中多次提到了任务队列，这里我们来讲一讲线程池中的一个很重要的参数：`BlockingQueue<Runnable> workQueue`，在线程池的生产者-消费者模型中，用户线程负责提交任务到线程池，worker线程负责从线程池中获取任务并执行，而阻塞队列`workQueue`就是生产者与消费者之间协调工作的桥梁，其实在上面讲解其他参数的过程中，`workQueue`已经多次出现了，但这里我们主要关注使用这个参数的两个地方：
1. `execute()`方法中通过`workQueue.offer()`方法提交任务到队列中
2. `getTask()`方法中通过`workQueue.take()`或者`workQueue.poll(timeout, unit)`从队列中获取工作任务

这两个地方就是阻塞队列协调worker线程与用户线程的主要方式，同时根据用户使用的队列实现不同，worker线程也会有不同的行为，例如如果使用`ArrayBlockingQueue`，那么就必须指定队列的长度，也就是有界队列，当队列满了之后，`offer()`的调用就会返回false，从而触发线程池增加worker或者拒绝任务的逻辑；如果使用`LinkedBlockingQueue`，并且`capacity`的值设置为`Integer.MAX_VALUE`，那么就会创建一个无界队列，只要内存足够大，那么就可以不断的向队列中添加任务；另外还可以使用`PriorityBlockingQueue`，这种带优先级排序的队列能够确保任务执行的顺序。具体使用哪一种队列，还是需要根据实际的应用场景来判断。

#### 线程工厂：threadFactory

上面提到的所有的参数都是创建线程池必须要指定的参数，而这里要讲的线程工厂并不是构造方法的必传参数，`ThreadPoolExecuter`也提供了另外的重载构造方法，设置了默认的`threadFactory`类，这里我把构造方法贴在这：

```java
public ThreadPoolExecutor(int corePoolSize,
                          int maximumPoolSize,
                          long keepAliveTime,
                          TimeUnit unit,
                          BlockingQueue<Runnable> workQueue) {
    this(corePoolSize, maximumPoolSize, keepAliveTime, unit, workQueue,
          Executors.defaultThreadFactory(), defaultHandler);
}
```

可以看到，在构造方法中，通过调用`Executors.defaultThreadFactory()`创建了一个默认的线程工厂对象，那么线程工厂对象的作用是什么呢？从命名我们可以大概猜到，应该是用于创建线程对象的，而线程对象在线程池中实际上都是通过内部类Worker包装起来的，我们先看一下Worker对象的构造方法：

```java
Worker(Runnable firstTask) {
    setState(-1); // inhibit interrupts until runWorker
    this.firstTask = firstTask;
    this.thread = getThreadFactory().newThread(this);
}
```

这里其实可以看到worker中的thread对象都是通过调用`threadFactory`的`newThread(this)`方法得到的，同时在创建线程时，将Worker对象本身作为`Runnable`对象传递给了线程，从这一点我们就可以了解到，当Worker线程开始执行的时候，就会调用Worker对象的`void run()`方法，而这个`run()`方法的实现，其实就是调用我们之前提到的`runWorker()`方法，代码如下：

```java
public void run() {
    runWorker(this);
}
```

线程池之所以提供`threadFactory`这样一个参数，是为使用者提供了一个控制线程对象创建的方式，我们可以通过自己需要的方式来创建线程对象，例如重写线程的run方法做一些额外的操作，修改线程的优先级，线程名称等等，这里我们可以简单看一下线程池默认使用的`threadFactory`实现：

```java
static class DefaultThreadFactory implements ThreadFactory {
    private static final AtomicInteger poolNumber = new AtomicInteger(1);
    private final ThreadGroup group;
    private final AtomicInteger threadNumber = new AtomicInteger(1);
    private final String namePrefix;

    DefaultThreadFactory() {
        SecurityManager s = System.getSecurityManager();
        group = (s != null) ? s.getThreadGroup() :
                              Thread.currentThread().getThreadGroup();
        namePrefix = "pool-" +
                      poolNumber.getAndIncrement() +
                      "-thread-";
    }

    public Thread newThread(Runnable r) {
        Thread t = new Thread(group, r,
                              namePrefix + threadNumber.getAndIncrement(),
                              0);
        if (t.isDaemon())
            t.setDaemon(false);
        if (t.getPriority() != Thread.NORM_PRIORITY)
            t.setPriority(Thread.NORM_PRIORITY);
        return t;
    }
}
```

从这段代码我们可以看到，其实这个`DefaultThreadFactory`的实现并不复杂，只不过是创建了一个线程组，并且把所有新创建的线程都归属到这个组中，并且以一致的命名方式为线程命名，以及设置相同的优先级。

#### 任务拒绝策略：RejectedExecutionHandler

在前面内容中多次提到了有限任务队列的情况下，提交给线程池的任务有可能被拒绝执行的情况，而这些被拒绝执行的任务我们往往不能直接把这些任务丢掉，而是会根据不同的业务场景执行不同的处理策略，于是这里线程池为我们提供了一个可选参数：`RejectedExecutionHandler handler`，我们可以实现`RejectedExecutionHandler`这个接口，来编写我们自己的拒绝执行策略。

在`execute()`方法中的最后一行调用了`reject(command)`方法，而这个方法的实现其实就是调用`RejectExecutionHandler`类的`rejectedExecution(Runnable r, ThreadPoolExecutor executor)`方法，如下：

```java
final void reject(Runnable command) {
    handler.rejectedExecution(command, this);
}
```

在线程池框架中其实已经为我们提供了4种不同的拒绝策略的实现，以供我们应对不同的应用场景，而线程池默认设置的拒绝策略是`AbortPolicy`，这个策略的实现其实非常简单，就是直接抛出一个`RejectExecutionException`异常：

```java
public void rejectedExecution(Runnable r, ThreadPoolExecutor e) {
    throw new RejectedExecutionException("Task " + r.toString() +
                                          " rejected from " +
                                          e.toString());
}
```

如果说我们实际场景中希望被拒绝的任务直接忽略掉，不抛出任何异常也不做任何处理的话，可以使用`DiscardPolicy`，这个实现更简单，直接是一个空方法，什么也不做：

```java
public void rejectedExecution(Runnable r, ThreadPoolExecutor e) {
}
```

另外还有两种策略：`DiscardOldestPolicy`和`CallerRunsPolicy`，这两种策略的实现方案也比较简单，其中`DiscardOldestPolicy`顾名思义就是扔掉队列中最早提交但尚未执行的task，然后将最新的task提交到队列中去等待执行，代码如下：

```java
public void rejectedExecution(Runnable r, ThreadPoolExecutor e) {
    if (!e.isShutdown()) {
        e.getQueue().poll(); // 这里poll()的作用就是从队列的head取出一个task对象并从队列中移除
        e.execute(r);
    }
}
```

`CallerRunsPolicy`就是当提交到线程池失败时，那就由提交线程（也就是生产者）自己来执行这个task，代码如下：

```java
public void rejectedExecution(Runnable r, ThreadPoolExecutor e) {
    if (!e.isShutdown()) {
        r.run();
    }
}
```

当然，如果觉得这4中策略都无法满足自己的业务场景，完全可以自己实现一个。

### 线程池的生命周期状态实现

一个线程池对象从创建开始，到终止所有线程并且对象被回收的过程中，可能会经历不同的阶段，`ThreadPoolExecuter`中给线程池定义了如下几个阶段：

* RUNNING: 可以接收新的任务并执行的阶段
* SHUTDOWN: 不接受新任务，但依然会处理队列中剩余的任务
* STOP: 不接受新任务，同时也不会处理队列中剩余的任务，并且会中断正在执行的任务
* TIDYING: 所有任务已经终止，并且worker数量为0，这个阶段线程开始执行terminated()方法，该方法由子类实现
* TERMINATED: 所有线程都已经执行完terminated()方法

在线程池的实现中，用一个32位的int值来的高3位来存储以上所说的运行状态值，其余的位数用于保存线程池中的worker数量，由于worker数量和线程池的状态是有关系的，这样做就可以用一个`AtomicInteger`变量来控制多个线程对状态和worker数量的修改，从而避免线程池状态和worker数量分开处理，从而需要增加额外的同步机制。

我们来看一下线程池中这些状态变量的定义：

```java
    private final AtomicInteger ctl = new AtomicInteger(ctlOf(RUNNING, 0));
    private static final int COUNT_BITS = Integer.SIZE - 3;
    private static final int CAPACITY   = (1 << COUNT_BITS) - 1;

    // runState is stored in the high-order bits
    private static final int RUNNING    = -1 << COUNT_BITS;
    private static final int SHUTDOWN   =  0 << COUNT_BITS;
    private static final int STOP       =  1 << COUNT_BITS;
    private static final int TIDYING    =  2 << COUNT_BITS;
    private static final int TERMINATED =  3 << COUNT_BITS;

    // Packing and unpacking ctl
    private static int runStateOf(int c)     { return c & ~CAPACITY; }
    private static int workerCountOf(int c)  { return c & CAPACITY; }
    private static int ctlOf(int rs, int wc) { return rs | wc; }
```

从上面的代码其实可以看到，`COUNT_BITS`的值是`Integer.SIZE - 3`，也就是29，那么上面所说的几个状态值的位级表示如下：

```text
RUNNING :    1110 0000 0000 0000 0000 0000 0000 0000
SHUTDOWN:    0000 0000 0000 0000 0000 0000 0000 0000
STOP:        0010 0000 0000 0000 0000 0000 0000 0000
TIDYING:     0100 0000 0000 0000 0000 0000 0000 0000
TERMINATED:  0110 0000 0000 0000 0000 0000 0000 0000
```

从上面的位模式可以看到，最高3位的值是从小到大递增的，而这些状态只能由小到大转换，也就是说无法从`SHUTDOWN`状态将线程池恢复到`RUNNING`状态，线程池也并未提供这样的方法。

基于上面的代码，我们可以看一下下面的那3个方法都分别做了什么，理解这3个方法的最好的方式就是通过位模式的变化来看，我们假设线程池中worker的数量为5，线程池状态是`RUNNING`，我们通过位模式的变化来看看下面的3个方法会产生什么结果：

```text
wc = 5 =             0000 0000 0000 0000 0000 0000 0000 0101  
rs = RUNNING =       1110 0000 0000 0000 0000 0000 0000 0000
c = ctlOf(rs, wc) =  1110 0000 0000 0000 0000 0000 0000 0101 (rs | wc)
CAPACITY =           0001 1111 1111 1111 1111 1111 1111 1111
runStateOf(c) =      1110 0000 0000 0000 0000 0000 0000 0000 (c & ~CAPACITY)
workerCountOf(c) =   0000 0000 0000 0000 0000 0000 0000 0101 (c & CAPACITY)
```

其实不难理解，这几个方法就是通过位运算的方式，获取32位int值中高3位和低29位的值。

在线程池实现中，针对上面的生命周期，`ThreadPoolExecutor`为我们提供了几个API，这几个API都是`ExecutorService`这个接口定义的，下面分别说一下这几个API的使用场景：

```java
void shutdown();
List<Runnable> shutdownNow();
boolean isShutdown();
boolean isTerminated();
boolean awaitTermination(long timeout, TimeUnit unit)
        throws InterruptedException;
```

首先说一下两个停止线程池中所有线程的方法`shutdown()`和`shutdownNow()`，二者的区别其实很简单，就像是正常关机和强制关机一样，`shutdown()`方法会通知所有idle线程触发中断，但仍然会将当前正在执行中的任务继续执行下去，而`shutdownNow()`会通知所有线程（包括正在执行任务的worker线程）触发中断，但会把当前线程池任务队列中的任务复制到一个List中返回，以便用户可以自己处理这些任务。

`isShutdown()`和`isTerminated()`只是判断线程池是否处于SHUTDOWN或TERMINATED状态，是则返回true，否则false。

`awaitTermination()`方法需要配合`shutdown()`使用，这个方法会使调用线程阻塞，直到线程池中所有正在进行的任务处于完成状态。

### 深入execute执行逻辑

在线程池中，我们使用频率最高的方法就是`void execute(Runnable command)`，所以这一节我们深入的看一下`execute()`在`ThreadPoolExecutor`中的执行逻辑，这里你可能会说最常用的方法不是`<T> Future<T> submit(Callable<T> task)` 吗？这里其实submit的实现是在`AbstractExecutorService`中定义的：

```java
public <T> Future<T> submit(Callable<T> task) {
    if (task == null) throw new NullPointerException();
    RunnableFuture<T> ftask = newTaskFor(task);
    execute(ftask);
    return ftask;
}
```

这里你可以清楚的看到，`submit()`方法最终还是会调用到`execute()`，只不过将原有的`Callable`或者`Runnable`对象，封装为了`RunnableFuture`对象，以便于获取task的返回值和异常信息。

其实上面为了讲清楚线程池的构造参数，多少讲了一些`execute`中的逻辑，但总体来说删减了很多逻辑，并且只关注重点的逻辑，这里希望从调用`execute()`方法开始，到线程执行完毕，通过分析代码把整体的流程串起来，从而对于线程池如何执行任务有个更清晰的认识，话不多说，先上代码：

下面的代码逻辑我会一段一段的解释，希望读者能够对照着JDK中完整的代码来理解

```java
    if (command == null)
        throw new NullPointerException();
```

`execute()`首先对于提交给线程池的任务做`null`的判断，如果`command == null`那么就直接抛出`NullPointerException`；

```java
 /*
  * Proceed in 3 steps:
  *
  * 1. If fewer than corePoolSize threads are running, try to
  * start a new thread with the given command as its first
  * task.  The call to addWorker atomically checks runState and
  * workerCount, and so prevents false alarms that would add
  * threads when it shouldn't, by returning false.
  *
  * 2. If a task can be successfully queued, then we still need
  * to double-check whether we should have added a thread
  * (because existing ones died since last checking) or that
  * the pool shut down since entry into this method. So we
  * recheck state and if necessary roll back the enqueuing if
  * stopped, or start a new thread if there are none.
  *
  * 3. If we cannot queue task, then we try to add a new
  * thread.  If it fails, we know we are shut down or saturated
  * and so reject the task.
  */
```

紧接着有一段代码注释，这个注释其实非常清楚的描述了接下来的执行逻辑，我们来简单翻译一下注释的内容：

下面的代码执行了如下3个步骤：
1. 如果线程的数量小于corePoolSize，尝试启动一个新的线程，并将command作为这个线程的第一个任务。在调用`addWorker`增加新线程时会检查`runState`和`workerCount`，并在无法添加新线程时返回false
2. 如果任务可以被成功添加到队列中，仍然需要针对是否要增加worker做一次double-check，因为已有的worker线程可能已经执行完毕或者线程池的状态可能变为SHUTDOWN。所以需要针对这两种情况做recheck，要么回滚已经入队的任务，要么创建新的线程替代原来结束的线程。
3. 如果任务无法入队（例如队列已满），那么尝试增加新的worker线程。如果增加线程失败，就拒绝这个任务，因为既无法增加新线程，也无法入队，要么就是线程池处于shut down状态，要么就是线程池已经满负荷。

对照上面的描述，我们来看一下下面的具体逻辑：

```java
int c = ctl.get(); // 这个ctl是的值是上面一节所说的状态变量，高3位存储runState，低29位存储workerCount值
// Step 1: workerCount < corePoolSize，直接调用addWorker()增加新线程，并把command做为worker的first task，然后return
if (workerCountOf(c) < corePoolSize) {
    if (addWorker(command, true))
        return;
    c = ctl.get(); // 这里如果addWorker调用返回false，那么说线程池的状态或worker数量被其他提交任务的线程更改了，所以需要重新获取状态变量
}
// Step 2: 如果线程池处于RUNNING状态，并且workerCount >= corePoolSize，那么将command入队等待执行
if (isRunning(c) && workQueue.offer(command)) {
    // 入队成功后，重新获取状态变量做double-check
    int recheck = ctl.get();
    // 如果线程池状态不在是RUNNING，删除队列中的command并执行拒绝策略
    if (! isRunning(recheck) && remove(command))
        reject(command);
    else if (workerCountOf(recheck) == 0) // 如果线程池仍处于RUNNING，检查一下worker线程数量是否为0，是则增加一个worker用于执行队列中的任务
        addWorker(null, false);
}
// Step 3: 如果上面两个步骤都未执行，那么尝试添加一个worker线程（这里和maxmiumPoolSize相关），添加失败则拒绝任务
else if (!addWorker(command, false))
    reject(command);
```

上面的代码我都加了注释，相信应该很容易理解，这里面比较难理解可能是那部分recheck的逻辑，这里我们可以想象一下，线程池对象就是为了解决多线程并发执行任务而存在的，因此同一时间肯定有多个线程在共同操作线程池，导致线程池的状态每时每刻都有可能发生变化，而这里的recheck操作其实就是为了更早的针对线程池状态的变化做出对应的处理，你会发现这里每做一个操作之前，都要重新get一下最新的线程池状态值，这也是为了确保并发情况下不会发生状态不一致的问题。

理解了上面的代码之后，我们其实并没有看到线程启动的代码，因为线程池既然要通过线程执行任务，那么就一定要调用`Thread.start()`方法启动这个线程，这个方法的调用其实就在`addWorker`方法中，下面我们来详细看一下这个方法的逻辑：

```java
boolean addWorker(Runnable firstTask, boolean core)
```

我们先看一下方法定义，这个方法有两个参数，其中`firstTask`是提交给线程的第一个任务，根据上面的逻辑，当`workerCount < corePoolSize`时，这个`firstTask`就是我们提交的`command`对象；第二个参数`core`是一个布尔值，如果为true则使用`corePoolSize`作为worker线程的数量边界，false则使用`maxmiumPoolSize`作为数量边界。

```java
// 这里的逻辑看上去比较乱，但本质上是一个：自旋+CAS 更新workerCount的过程，因为多个线程会同时调用这个方法，因此必须要根据线程池的状态和当前的worker数量对这些线程进行同步，以此确保workerCount的值是正确的
retry:
for (;;) {
    // 首先在做下面操作之前，取出当前的状态变量，并解析出runState的值
    int c = ctl.get();
    int rs = runStateOf(c);

    // 这里又是一个recheck的逻辑，在增加workerCount之前，先判断线程池的状态>=SHUTDOWN，
    // 并且任务队列是空的，这时就不需要创建新的worker，只需要保证现有的worker最终结束即可，正常的RUNNING状态会直接跳过这断逻辑
    // Check if queue empty only if necessary.
    if (rs >= SHUTDOWN &&
        ! (rs == SHUTDOWN &&
            firstTask == null &&
            ! workQueue.isEmpty()))
        return false;

    // 下面通过 自旋+CAS操作确保 workerCount 自增成功
    for (;;) {
        int wc = workerCountOf(c);
        if (wc >= CAPACITY ||
            wc >= (core ? corePoolSize : maximumPoolSize)) // 这里根据 core 的值(true/false)确定wc的边界，超过边界则不再增加worker，直接返回false
            return false;
        if (compareAndIncrementWorkerCount(c)) // CAS自增操作，成功则跳出自旋，失败则自旋重试，注意这里重试是走内循环重试
            break retry;
        c = ctl.get();  // Re-read ctl
        if (runStateOf(c) != rs) // 每次在CAS自增workerCount失败时，检查一下线程池的runStat是否有变化，如果有变化则跳转到外层循环重新做recheck逻辑
            continue retry;
        // 下面的注释：如果runState没有变化，那么CAS因为workerCount被其他线程修改而失败，重试内层循环
        // else CAS failed due to workerCount change; retry inner loop
    }
}
```

上面我加了很多的代码注释，以便于更好的理解这里的逻辑，其实这部分代码主要目标就是：**自增workerCount的值**，只有针对workerCount的自增操作成功之后，才可以真正创建worker线程对象，这一点我认为是处于线程安全和效率的双重考虑，只有自增成功的线程，才能继续执行下面的逻辑，同时下面创建worker对象如果失败了，也要把这个workerCount的值回滚，确保线程池状态值和实际的worker数量保持一致，下面看一下创建worker对象的代码：

```java
boolean workerStarted = false;
boolean workerAdded = false;
Worker w = null;
try {
    // 这里直接创建Worker对象，传入firstTask对象作为worker执行的第一个任务
    w = new Worker(firstTask);
    final Thread t = w.thread; // 注意这里的thread对象是由ThreadFactory创建的，有可能为空值，如果为空就直接跳过这段逻辑，执行finally部分
    if (t != null) {
        // 这里的 mainLock 主要针对 workers 和 largestPoolSize这两个共享变量加锁，因为这两个变量都没有定义为线程安全对象
        final ReentrantLock mainLock = this.mainLock;
        mainLock.lock();
        try {
            // Recheck while holding lock.
            // Back out on ThreadFactory failure or if
            // shut down before lock acquired.
            int rs = runStateOf(ctl.get());
            // 这里再次针对线程池状态runState做recheck，
            if (rs < SHUTDOWN ||
                (rs == SHUTDOWN && firstTask == null)) {
                if (t.isAlive()) // 如果这个线程已经被启动，那么直接抛出异常
                    throw new IllegalThreadStateException();
                workers.add(w); // 将worker对象添加到 worker set，这是一个HashSet对象
                int s = workers.size();
                if (s > largestPoolSize) // 更新线程池中线程最大数量
                    largestPoolSize = s;
                workerAdded = true;
            }
        } finally {
            mainLock.unlock();
        }
        // 当走到这里才开始启动线程
        if (workerAdded) {
            t.start();
            workerStarted = true;
        }
    }
} finally {
    // 如果启动线程失败，则通过这段逻辑回滚线程池状态
    if (! workerStarted)
        addWorkerFailed(w);
}
return workerStarted;
```

通过这段代码逻辑，我们看到代码中出现了`t.start()`，也就是启动了线程，那么启动的线程到底执行的逻辑是什么呢？这里我们需要进一步的看`Worker`的内部实现：

```java
private final class Worker
    extends AbstractQueuedSynchronizer
    implements Runnable
{
    Worker(Runnable firstTask) {
        setState(-1); // inhibit interrupts until runWorker
        this.firstTask = firstTask;
        this.thread = getThreadFactory().newThread(this);
    }

    /** Delegates main run loop to outer runWorker  */
    public void run() {
        runWorker(this);
    }
}
```

这里我只给出了构造方法和`run()`方法的实现，以及`Worker`定义中的继承结构，其实`Worker`对象本身就是一个`Runnable`的对象，并且`run()`方法的实现就是直接调用线程池的`runWorker()`方法，并把`this`作为参数传递过去，因此当上面执行`t.start()`时，这里的`run()`方法就会执行，从而执行到`runWorker(this)`。

这里我们先把`runWorker`的逻辑放到一边，先来看看如果`worker`线程启动失败，`addWorkerFailed()`方法中的逻辑是怎样的：

```java
private void addWorkerFailed(Worker w) {
    final ReentrantLock mainLock = this.mainLock;
    mainLock.lock();
    try {
        if (w != null)
            workers.remove(w); //首先从workers set 中移除新增的worker对象
        decrementWorkerCount(); // 然后通过CAS+自旋的方式将worker的数量减1
        tryTerminate();  // 这里是尝试终止线程池，如果线程池处于RUNNING状态，那么这个方法不会做任何操作
    } finally {
        mainLock.unlock();
    }
}
```

上面`tryTerminate()`的逻辑我们这里不详细去讲，需要了解的自行看源码即可，那么我们再回头来说说`runWorker`的逻辑：

```java
final void runWorker(Worker w) {
    Thread wt = Thread.currentThread();
    Runnable task = w.firstTask;
    w.firstTask = null;
    // 这里为什么要执行 unlock()，需要了解AQS框架才能说清楚，因此这里不做解释，留给读者自行探索
    w.unlock(); // allow interrupts
    boolean completedAbruptly = true;
    try {
        // 如果firstTask不为空，那么执行firstTask，否则就通过getTask()从队列中获取task对象
        while (task != null || (task = getTask()) != null) {
            w.lock();
            // If pool is stopping, ensure thread is interrupted;
            // if not, ensure thread is not interrupted.  This
            // requires a recheck in second case to deal with
            // shutdownNow race while clearing interrupt
            // 在执行task之前先判断一下线程池状态是否处于STOP阶段，是则设置线程中断状态
            if ((runStateAtLeast(ctl.get(), STOP) ||
                  (Thread.interrupted() &&
                  runStateAtLeast(ctl.get(), STOP))) &&
                !wt.isInterrupted())
                wt.interrupt();
            try {
                // 线程池的一个扩展点，用于在执行task之前做一些前处理工作
                beforeExecute(wt, task);
                Throwable thrown = null;
                try {
                    // 执行task.run()方法执行用户提交的任务
                    task.run();
                // 将异常对象引用保留在 thrown变量中，把原始的异常直接抛出
                } catch (RuntimeException x) {
                    thrown = x; throw x;
                } catch (Error x) {
                    thrown = x; throw x;
                } catch (Throwable x) {
                    thrown = x; throw new Error(x);
                } finally {
                    // 后处理的扩展点
                    afterExecute(task, thrown);
                }
            } finally {
                // 线程执行完成之后，增加worker的completedTasks计数
                task = null;
                w.completedTasks++;
                w.unlock();
            }
        }
        completedAbruptly = false;
    } finally {
        // Worker线程执行完成之后，处理线程退出逻辑，通过completedAbruptly判断是正常退出还是中断退出
        processWorkerExit(w, completedAbruptly);
    }
}
```

这里我在上面关键代码位置加了注释，整体来讲就是通过`getTask`获取任务对象，然后调用`task.run()`执行task，并且在执行前后分别做前后处理，最终回收worker线程，其中`getTask()`和`processWorkerExit()`的逻辑在之前有提过，这里留给读者自行理解其中的实现细节。

## 总结

最后总结一下我这篇源码分析的整体知识脉络，首先我通过线程池框架要解决的核心问题引出了线程池的整体设计：生产者-消费者模式；接下来我着重分析了`ThreadPoolExecutor`的构造方法提供的参数，针对每个参数都对照代码实现细节做了详细的讲解；然后我针对线程池的生命周期状态变量的实现做了说明，这个状态变量是通过一个`AtomicInteger`包装了一个32位int值，用高3位代表运行状态，后29位代表worker数量；最后我通过详细的讲解`execute()`方法的执行过程，说明了几乎每一行代码所做的事情。

当然其实还有很多的实现细节我这里没有讲，因为要完全将这些细节讲清楚，可能需要更细致的研究以及更大的篇幅来说清楚，因此这里没有再继续深入，希望这篇文章能够对读者有帮助。