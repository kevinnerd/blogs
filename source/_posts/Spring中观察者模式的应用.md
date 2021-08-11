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

**观察者模式(Observer Pattern)**，有时也称作**发布-订阅模式(Publish-Subscribe Pattern)**是工程中比较常见的一种面向对象设计模式，这种模式通常被用于解耦一些联系紧密，但又具备不同职责的对象，通过这种模式来使多个合作的对象之间达到一种一致的状态，而对象本身的代码逻辑又能独立维护，我们通常所说的**事件监听**其实就是这种模式的应用。

在本篇文章中，我通过分析Spring中的几个关于事件发布订阅的核心API以及代码实现，来讲解这种设计模式在实际项目中如何使用。同时也加深一下自己对于Spring容器中消息分发机制的理解。

## 观察者模式简介

在经典的设计模式书籍《Design Patterns-GOF》中，关于观察者模式有如下的描述：

> Define a one-to-many dependency between objects so that when one object changes state, all its dependents are notified and updated automatically.

通过上面的描述其实不难理解，所谓观察者模式，本质上就是多个对象同时观察(或者说监听)某个对象的状态变化，从而自动的做出相应的处理，其实在实际的业务场景中这种情况很常见，例如当我们在淘宝上下了一个订单，那么当这个订单状态由待支付变为已支付时，这就相当于订单的状态发生了改变，从而淘宝后台的很多系统，例如物流，库存等等，都需要根据这个状态而进行对应的处理，这其实就可以通过观察者模式来解决多个系统之间的耦合问题，当然多个不同系统之间的解耦肯定要比对象之间的解耦复杂的多，但本质的思想是一样的。

在最简单的观察者模式实现中，通常要有两个关键的对象：Subject, Observer。 其中Subject就是被观察的对象，而Observer就是观察者，下面我们来看一下这种最简单的观察者模式的类图：



### Subject

### Observer

### ChangeManager

## Spring容器中的观察者模式

### ApplicationEventPublisher

### EventListener

### ApplicationEventMulticaster