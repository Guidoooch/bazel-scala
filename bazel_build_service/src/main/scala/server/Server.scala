package server

import domain.Request

object Server extends App {

  println("I'm the server!")

  private val request = Request("target")
  println(s"Target requested: ${request.target}")
}