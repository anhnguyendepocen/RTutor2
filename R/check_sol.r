# Functions for checking student solutions
# Tests are implemented in in tests_for_ps.r

#' Checks a student problem set
#'
#' The command will be put at the top of a student's problem set. It checks all exercises when the problem set is sourced. If something is wrong, an error is thrown and no more commands will be sourced.
#'@export
check.problem.set = function(ps.name,stud.path, stud.short.file, reset=FALSE, set.warning.1=TRUE, user.name="GUEST", do.check=interactive(), verbose=FALSE, catch.errors=TRUE, from.knitr=!interactive(), use.null.device=TRUE, just.init=FALSE) {

  restore.point("check.problem.set", deep.copy=FALSE)


  if (from.knitr) {
    # Allows knitting to HTML even when there are errors
    knitr::opts_chunk$set(error = TRUE)
    ps = NULL
    try(ps <- get.or.init.ps(ps.name,user.name, stud.path, stud.short.file, reset), silent=TRUE)

    # Copy extra code into globalenv
    if (!is.null(ps$rps$extra.code.env)) {
      copy.into.env(source=ps$rps$extra.code.env, dest = globalenv())
    }
    return()
  }

  # If called from knitr, I don't want to check by default
  if (!do.check) return("not checked")



  if (set.warning.1) {
    if (options()$warn<1)
      options(warn=1)
  }
  if (!isTRUE(try(file.exists(stud.path),silent = TRUE))) {
    str= paste0("I could not find your problem set directory '", stud.path,"'.  Please set in the first code chunk of the your problem set the variable 'ps.dir' to the directory in which you have saved your problem set.

Note: use / instead of \\ to separate folders in 'ps.dir'")
    stop(str,call. = FALSE)
  }
  if (!file.exists(paste0(stud.path,"/", stud.short.file))) {
    str= paste0("I could not find your file '", stud.short.file,"' in your problem set folder '",stud.path,"'. Please set the variables ps.dir and ps.file to the right values in the first chunk of your problem set. The variable 'ps.file' must have the same file name than your problem set file.")
    stop(str,call. = FALSE)
  }

  setwd(stud.path)

  if (user.name=="ENTER A USER NAME HERE") {
    stop('You have not picked a user name. Change the variable "user.name" in your problem set file from "ENTER A USER NAME HERE" to some user.name that you can freely pick.',call. = FALSE)
  }

  log.event(type="check_ps")

  if (verbose)
    display("get.or.init.ps...")

  ps = get.or.init.ps(ps.name,user.name,stud.path, stud.short.file, reset)
  ps$catch.errors = catch.errors
  ps$use.null.device = use.null.device

  set.ps(ps)
  ps$warning.messages = list()

  cdt = ps$cdt
  edt = ps$edt

  ps$stud.code = readLines(ps$stud.file)
  cdt$stud.code = get.stud.chunk.code(ps=ps)
  cdt$code.as.shown = cdt$stud.code == cdt$shown.txt
  cdt$chunk.changed = cdt$stud.code != cdt$old.stud.code
  cdt$old.stud.code = cdt$stud.code

  #test.code.df = data.frame(stud.code = cdt$stud.code, old.stud.code = cdt$old.stud.code)

  ex.changed = summarise(group_by(as.data.frame(cdt),ex.ind), ex.changed = any(chunk.changed))$ex.changed

  ex.check.order = unique(c(which(ex.changed),ps$ex.last.mod, which(!edt$ex.solved)))

  if (! any(cdt$chunk.changed)) {
    code.change.message = "\nBTW: I see no changes in your code... did you forget to save your file?"
  } else {
    code.change.message = NULL
  }

  ps$cdt = cdt

  if (just.init) return(invisible())

  # Check exercises
  i = 1
  # i = 8
  for (i in ex.check.order) {
    ps$ex.last.mod = i
    ex.name = edt$ex.name[i]
    ret <- FALSE
    if (verbose) {
      display("### Check exercise ", ex.name ," ######")
    }

    if (!is.false(ps$catch.errors)) {
      ret = tryCatch(check.exercise(ex.ind=i, verbose=verbose),
                   error = function(e) {ps$failure.message <- as.character(e)
                                        return(FALSE)})
    } else {
      ret = check.exercise(ex.ind=i, verbose=verbose)
    }
    # Copy variables into global env
    copy.into.envir(source=ps$task.env,dest=.GlobalEnv, set.fun.env.to.dest=TRUE)
    save.ups()
    if (ret==FALSE) {
      edt$ex.solved[i] = FALSE
      if (cdt$code.as.shown[ps$chunk.ind]) {
        message = paste0("You have not yet started with chunk ", cdt$chunk.name[ps$chunk.ind],"\nIf you have no clue how to start, try hint().")
        #cat(message)
        stop.without.error(message)
      }

      message = ps$failure.message
      message = paste0(message,"\nFor a hint, type hint() in the console and press Enter.")
      message = paste(message,code.change.message)


      stop(message, call.=FALSE, domain=NA)
    } else if (ret=="warning") {
      message = paste0(ps$warning.messages,collapse="\n\n")
      message(paste0("Warning: ", message))
    }
    edt$ex.solved[i] = TRUE
  }

  if (all(edt$ex.solved)) {
    display("\n****************************************************")
    stats()
    msg = "You solved the problem set. Congrats!"
    stop.without.error(msg)
  }
  stop("There were still errors in your solution.")
}

check.exercise = function(ex.ind, verbose = FALSE, ps=get.ps(), check.all=FALSE) {
  restore.point("check.exercise")

  ck.rows = ps$cdt$ex.ind == ex.ind
  cdt = ps$cdt
  ex.name = ps$edt$ex.name[ex.ind]

  if (check.all) {
    min.chunk = min(which(ck.rows))
  } else {
    rows = which(ck.rows & ((!cdt$is.solved) | cdt$chunk.changed))
    # All chunks solved and no chunk changed
    if (length(rows)==0) {
      cat(paste0("\nAll chunks were correct and no change in exercise ",ex.name,"\n"))
      return(TRUE)
    }
    min.chunk = min(rows)
  }
  chunks = min.chunk:max(which(ck.rows))
  chunk.ind = chunks[1]
  for (chunk.ind in chunks) {
    ret = check.chunk(chunk.ind,ps=ps, verbose=verbose)
    if (ret==FALSE) {
      return(FALSE)
    }
  }
  if (NROW(ps$edt)==1) {
    # otherwise data.table throws strange error
    ps$edt$ex.final.env[[ex.ind]] = list(copy(ps$task.env))
  } else {
    ps$edt$ex.final.env[[ex.ind]] = copy(ps$task.env)
  }
  return(TRUE)
}


can.chunk.be.edited = function(chunk.ind, ps = get.ps()) {
  restore.point("can.chunk.be.edited")

  cdt = ps$cdt
  ck = cdt[chunk.ind,]
  ex.ind = ck$ex.ind


  non.optional = which(cdt$ex.ind == ex.ind & !cdt$optional)
  if (length(non.optional)==0) {
    start.ex = TRUE
  } else {
    first.ind = non.optional[1]
    start.ex = chunk.ind <= first.ind
  }

  if (start.ex) {
    if (ex.ind==1)
      return(TRUE)
    ex.names = names(ps$edt$import.var[[ck$ex.ind]])
    if (is.null(ex.names))
      return(TRUE)
    edt = ps$edt
    ex.inds = edt$ex.ind[match(ex.names,edt$ex.name)]

    chunks = which(ps$cdt$ex.ind %in% ex.inds)
    solved = all(ps$cdt$is.solved[chunks] | ps$cdt$optional[chunks])
    if (all(solved))
      return(TRUE)
    ps$failure.message = paste0("You must first solve and check all chunks in exercise(s) ", paste0(ex.names[ex.inds],collapse=", "), " before you can start this exercise.")
    return(FALSE)
  } else {
    ex.rows = which(cdt$ex.ind == ex.ind & cdt$chunk.ps.ind < chunk.ind)
    if (all(ps$cdt$is.solved[ex.rows] | ps$cdt$optional[ex.rows])) {
      return(TRUE)
    }

    ps$failure.message = paste0("You must first solve and check all previous, non-optional chunks in this exercise before you can edit and solve this chunk.")
    return(FALSE)
  }

}

#' Extracts the stud's code of a given exercise
#' @export
extract.exercise.code = function(ex.name,stud.code = ps$stud.code, ps=get.ps(),warn.if.missing=TRUE) {
  restore.point("extract.r.exercise.code")

  return(extract.rmd.exercise.code(ex.name,stud.code, ps,warn.if.missing))
}

extract.rmd.exercise.code = function(ex.name,stud.code = ps$stud.code, ps=get.ps(),warn.if.missing=TRUE) {
  restore.point("extract.rmd.exercise.code")
  txt = stud.code
  mr = extract.command(txt,paste0("## Exercise "))
  mr[,2] = str_trim(gsub("#","",mr[,2], fixed=TRUE))
  start.ind = which(mr[,2]==ex.name)
  start.row = mr[start.ind,1]
  if (length(start.row) == 0) {
    if (warn.if.missing)
      message(paste0("Warning: Exercise ", ex.name, " not found. Your code must have the line:\n",
                     paste0("## Exercise ",ex.name)))
    return(NA)
  }
  if (length(start.row)>1) {
    message("Warning: Your solution has ", length(start.row), " times exercise ", ex.name, " I just take the first.")
    start.row = start.row[1]
    start.ind = start.ind[1]
  }
  end.row = c(mr[,1],length(txt)+1)[start.ind+1]-1
  str = txt[(start.row+1):(end.row)]

  # Get all code lines with an R code chunk
  hf = str.starts.with(str,"```")
  str = str[cumsum(hf) %% 2 == 1 & !hf]

  paste0(str, collapse="\n")
}

get.stud.chunk.code = function(txt = ps$stud.code,chunks = ps$cdt$chunk.name, ps = get.ps()) {
  restore.point("get.stud.chunk.code")
  chunk.start = which(str.starts.with(txt,"```{"))
  chunk.end   = setdiff(which(str.starts.with(txt,"```")), chunk.start)
  chunk.end = remove.verbatim.end.chunks(chunk.start,chunk.end)

  # remove all chunks that have no name (initial include chunk)
  chunk.name = str.between(txt[chunk.start],'"','"', not.found=NA)

  na.chunks  = is.na(chunk.name)
  chunk.start= chunk.start[!na.chunks]
  chunk.end  = chunk.end[!na.chunks]
  chunk.name = chunk.name[!na.chunks]

  chunk.txt = sapply(seq_along(chunk.start), function (i) {
      if (chunk.start[i]+1 > chunk.end[i]-1) return("")
      code = txt[(chunk.start[i]+1):(chunk.end[i]-1)]
      paste0(code, collapse="\n")
  })

  names(chunk.txt) = chunk.name
  chunk.txt = chunk.txt[chunk.name %in% chunks]

  if (!identical(names(chunk.txt), chunks)) {
    missing.chunks = paste0(setdiff(chunks, chunk.name),collapse=", ")
    stop("I miss chunks in your solution: ",missing.chunks,". You probably removed them or changed the title line or order of your chunks by accident. Please correct this!", call.=FALSE)
  }
  chunk.txt
}


make.chunk.task.env = function(chunk.ind, ps = get.ps()) {
  restore.point("make.chunk.task.env")

  # return emptyenv if no student code
  # shall ever be evaluated
  if (isTRUE(ps$noeval)) {
    return(emptyenv())
  }


  # return precomputed chunkenv
  if (isTRUE(ps$precomp)) {
    task.env = copy.task.env(ps$cdt$task.env[[chunk.ind]], chunk.ind)
    return(task.env)
  }


  ck = ps$cdt[chunk.ind,]

  cdt = ps$cdt

  # Find index of closest non-optional parent
  ex.ind = ck$ex.ind
  non.optional = which(cdt$ex.ind == ex.ind & !cdt$optional)
  non.optional = non.optional[non.optional < chunk.ind]

  if (length(non.optional)==0) {
    start.ex = TRUE
  } else {
    parent.ind = max(non.optional)
    start.ex = FALSE
  }


  if (start.ex) {
    # First chunk in exercise: generate new task.env
    task.env = new.task.env(chunk.ind)
    import.var.into.task.env(ps$edt$import.var[[ck$ex.ind]], task.env,ps)

  } else {
    # Later chunk in an exercise: simply copy previous task.env
    task.env = copy.task.env(ps$cdt$task.env[[parent.ind]], chunk.ind)
  }
  task.env
}


# Import variables from other exercises task.env's
import.var.into.task.env = function(import.var, dest.env, ps = get.ps()) {
  restore.point("import.var.into.task.env")
  if (is.null(import.var))
    return(NULL)
  restore.point("import.var.into.task.env2")

  #stop("jbhgbhbdgh")
  i = 1
  edt = ps$edt
  ex.names = edt$ex.name

  for (i in seq_along(import.var)) {
    ex.name = names(import.var)[i]
    if (!ex.name %in% ex.names) {
      ind = str.starts.with(ex.names,ex.name)
      if (!any(ind)) {
        stop(paste0("\nWrong import variable statement in solution file of exercise  ",ex.names[i], ": exercise ", ex.name, " not found"))
      } else {
        ex.name = ex.names[ind][1]
      }
    }

    vars = import.var[[i]]
    ex.ind = which(edt$ex.name==ex.name)
    source.env = edt$ex.final.env[[ex.ind]]
    if (is.null(source.env)) {
      #str = paste0("\nYou must first solve and check exercise '", ex.name, " before you can solve this exercise.\n To check exercise ", ex.name, " enter somewhere an irrelevant space in it's code chunks.")
      ck$log$failure.message = str
      stop(str)
      return(FALSE)
    }
    for (var in vars) {
      if (!exists(var,source.env, inherits=FALSE)) {
        str = paste0("You first must correctly generate the variable '", var, "' in exercise ", ex.name, " before you can solve this exercise.")
        ck$log$failure.message = str
        stop(str)
      }
      val = get(var,source.env)
      # Set enclosing environments of functions to dest.env
      if (is.function(val))
        environment(val) = dest.env
      assign(var, val,dest.env)
    }
  }
  return(TRUE)
}


