<?php
/**
 * Class to process ZD tickets.
 */

abstract class ZendeskTicketProcessor {
  protected $ticket;
  protected $action_queue = array();
  protected $action_types = ['postCommentAndFile', 'postComment'];
  protected $storage = array();

  function __construct($ticket) {
    date_default_timezone_set("America/New_York");
    $this->ticket = $ticket;
  }

  function log($msg) {
    echo date("H:i:s ");
    echo '[ZD ' . $this->ticket->id . ']';
    echo ' \\' . get_class($this) . ":";
    echo debug_backtrace()[1]['function'] . "() -> $msg\n";
  }

  // Add an action to the queue.
  function queueAction($action) {
    if (!isset($action['type'])) {
      die("ERROR: queueAction(): Missing action type");
    }
    if (!in_array($action['type'], $this->action_types)) {
      die("ERROR: Wrong ticket action type " . $action['type']);
    }
    $this->action_queue[] = $action;
    $this->log("Queued the action " . $action['type']);
  }

  // Execute all queued actions.
  function runActionQueue() {
    foreach ($this->action_queue as $action) {
      $this->runAction($action);
    }
  }

  // Execute a single action from the queue.
  function runAction($action) {
    switch ($action['type']) {
      case "postCommentAndFile":
        $this->log("Running queued action " . $action['type']);
        zendesk_post_comment_and_file(
          $this->ticket->id,
          $action['args']['comment_body'],
          $action['args']['infile'],
          $action['args']['is_public']
        );
        break;
      case "postComment":
        $this->log("Running queued action " . $action['type']);
        zendesk_post_comment(
          $this->ticket->id,
          $action['args']['comment_body'],
          isset($action['args']['is_public']) ? $action['args']['is_public'] : false
        );
        break;
    }
  }

  // Return true when the ticket meets the requirements.
  function ticketMeetsRequirements() {
    if (empty($this->ticket->id)) {
      return false;
    }
    return true;
  }

  function processTicket() {
    return true;
  }

  function execute() {
    // Check if this ticket meets the filters.
    if (!$this->ticketMeetsRequirements()) {
      return;
    }
    // Process the ticket
    $this->processTicket();

    // Run queue of resulting actions.
    $this->runActionQueue();
  }
}

class ZendeskTicketProcessorAhtpanicrunner extends ZendeskTicketProcessor {

  // Extract URLs from textfield.
  function parseUrls($text) {
    $urls = array();
    foreach (preg_split("/[\s,]+/", trim($text)) as $line) {
      $line = trim($line);
      if (stripos($line, "http") === FALSE) {
        $line = "http://" . $line;
      }
      if (parse_url($line) !== FALSE) {
        // Extract host from each URL.
        $parsed = parse_url($line);
        if ($parsed && !empty($parsed['scheme']) && !empty($parsed['host'])) {
          $urls[] = strtolower($parsed['scheme']) . '://' . strtolower($parsed['host']);
        }
      }
    }
    return $urls;
  }

  // Extract URLs via regex
  function extractUrlsRegex($text) {
    $urls = [];
    preg_match_all("/[a-z][a-z][a-z0-9]*\.[a-z0-9][a-z0-9][a-z0-9\.-]*[a-z0-9]/", $text, $results);
    // Extract first string that looks like a domain that actually returns an IP
    // AND meets valid URLs.
    foreach ($results[0] as $result) {
      if (FALSE !== gethostbynamel($result)) {
        if (strpos($result, ".acquia.com") === FALSE) {
          $urls[] = $result;
        }
      }
      else {
        if (@dns_get_record($result)) {
          $urls[] = $result;
        }
      }
    }
    return $urls;
  }

  // Make sure any example URL used belongs to an Acquia site
  function domainIsAcquiaHosted($domain) {
    $not_acquia = exec('aht find:domain ' . $domain .' --no-ansi |grep -c "not found"');
    return ($not_acquia == "0");
  }

  // Filter out any non-acquia domains
  function filterAcquiaHostedDomains($domains) {
    foreach ($domains as $index => $domain) {
      if (!$this->domainIsAcquiaHosted($domain)) {
        unset($domains[$index]);
      }
    }
    return $domains;
  }


  // Determines if we will process this ticket or not.
  function ticketMeetsRequirements() {
    // Get the example URLs field from ticket. (Which is a Textfield)
    $example_urls = zendesk_get_custom_field($this->ticket, 23786337);
    if ($example_urls && !empty($example_urls->value)) {
      // Extract URLs from text.
      $urls = $this->parseUrls($example_urls->value);

      // Remove some URLs
      foreach ($urls as $n => $url) {
        if (
            #domains that have acquia.com in the domain
            strpos($url, ".acquia.com") !== FALSE
            #domains that have example.com in the domain
            || strpos($url, ".example.com") !== FALSE
            # Some common domains which aren't valid
            || strpos($url, "youtube.com") !== FALSE
            || strpos($url, "google.com") !== FALSE
          ) {
          $this->log("Ignoring mentioned example URL $url");
          unset($urls[$n]);
        }
      }

      if (count($urls)>0) {
        $acquia_filtered_urls = $this->filterAcquiaHostedDomains($urls);
        if (count($acquia_filtered_urls) == 0) {
          $this->log("No example URLs belong to Acquia Hosting: " . implode(' ', $urls));
        }
        $urls = $acquia_filtered_urls;
        // Store the hostname to trigger on.
        $this->storage['url'] = reset($urls);
        if (count($urls)>1) {
          $this->log("More than one example URL found, using first one only.");
        }
      }
    }

    // If no URLs found, try a fallback.
    if (empty($this->storage['url'])) {
      // Fallback 1: proactive ops tickets with a certain subject line
      if ($this->ticket->subject == "Service Interruption Detected on your Production Environment") {
        // Get the docroot using CCI.
        $docroot = $this->getSitenameFromSubscription();
        if ($docroot) {
          $this->storage['url'] = 'http://' . $docroot . '.prod.acquia-sites.com';
          // Override if site looks like ACSF.
          // @TODO: Better detection method?
          if (stripos($this->ticket->description, "ACSF") !== FALSE) {
            $this->storage['url'] = 'http://' . $docroot . '01live.enterprise-g1.acquia-sites.com';
          }
          // We do not want to run the further URL checks below, so let's return now.
          return parent::ticketMeetsRequirements();
        }
      }

      // Fallback: text from the ticket title has 1+ URLs
      if (empty($this->storage['url']) && $urls = $this->extractUrlsRegex($this->ticket->subject)) {
        // Filter for only valid URLs
        $urls = $this->filterAcquiaHostedDomains($urls);
        if ($url = reset($urls)) {
          $this->storage['url'] = $url;
          $this->log("URL detection fallback: Found URLs in ticket subject.");
        }
      }
      // Fallback: text from the ticket description has 1+ URLs
      if (empty($this->storage['url']) && $urls = $this->extractUrlsRegex($this->ticket->description)) {
        // Filter for only valid URLs
        $urls = $this->filterAcquiaHostedDomains($urls);
        if ($url = reset($urls)) {
          $this->storage['url'] = $url;
          $this->log("URL detection fallback: Found URLs in ticket description.");
        }
      }
      // Fallback: text on the ticket description that matches /mnt/www/html/[sitename-with-dots]
      if (empty($this->storage['url']) && preg_match('%/mnt/(www/html|gfs)/([a-z][a-z0-9]*\.[a-z0-9]*)/%', $this->ticket->description, $matches)) {
        $sitename = $matches[2];
        $this->storage['url'] = '@' . $sitename;
        $this->log("URL detection fallback: Found " . $matches[0] . " in ticket subject, using URL " . $this->storage['url']);
        // We do not want to run the further URL checks below, so let's return now.
        return parent::ticketMeetsRequirements();
      }
      // Fallback: text on the ticket description that matches /mnt/www/html/[sitename-with-NO-dots]
      if (empty($this->storage['url']) && preg_match('%/mnt/(www/html|gfs)/([a-z][a-z0-9]*)/%', $this->ticket->description, $matches)) {
        $sitename = $matches[2];
        $this->storage['url'] = "http://{$sitename}.prod.acquia-sites.com";
        $this->log("URL detection fallback: Found " . $matches[0] . " in ticket subject, using URL " . $this->storage['url']);
      }
      // Fallback: text on the ticket description that matches /var/www/site-php/[sitename-with-no-dots]
      if (empty($this->storage['url']) && preg_match('%/var/www/site-php/([a-z][a-z0-9]*)/([a-z][a-z0-9]*)-%', $this->ticket->description, $matches)) {
        if ($matches[1] === $matches[2]) {
          $sitename = $matches[1];
          $this->storage['url'] = "http://{$sitename}.prod.acquia-sites.com";
          $this->log("URL detection fallback: Found " . $matches[0] . " in ticket subject, using URL " . $this->storage['url']);
        }
      }
    }

    // Make sure any example URL used belongs to an Acquia site
    if (!empty($this->storage['url'])) {
      if (!$this->domainIsAcquiaHosted($this->storage['url'])) {
        $this->log("No acquia site found associated to URL " . $this->storage['url']);
        unset($this->storage['url']);
      }
    }

    // If fallbacks got nothing, then return FALSE;
    if (empty($this->storage['url'])) {
      $this->log("Could not determine URL (or @site.env) to run checks on.");
      return FALSE;
    }

    return parent::ticketMeetsRequirements();
  }

  function getSitenameFromSubscription() {
    $uuid = zendesk_get_custom_field($this->ticket, 23786347);
    if (!empty($uuid->value)) {
      exec(
        "aht cci request aht/subscription/{$uuid->value}/info --format=json",
        $output,
        $return_var
      );
      if ($json = json_decode(implode('', $output))) {
        return $json->docroot;
      }
    }
    return false;
  }

  function runCommandWithTimeout($cmd, $timeout) {
    if (!is_numeric($timeout)) {
      die("ERROR: timeout needs to be a number");
    }
    $real_cmd = "timeout {$timeout} $cmd";
    $this->log("Running command $real_cmd");
    $start_time = time();
    exec($cmd, $result_output, $result_code);
    $elapsed_time = time() - $start_time;
    $this->log("Command finished. Took $elapsed_time seconds");

    return [
      'result_output' => implode("\n", $result_output),
      'result_code' => $result_code,
      'elapsed_time' => $elapsed_time,
      'timed_out' => ($result_code == "124"),
    ];
  }

  // Clean up both output files for a "second chance"
  function removeOutputFiles($output_basename) {
    @unlink("{$output_basename}.txt");
    @unlink("{$output_basename}-summary.txt");
  }

  // Function that look at each ticket and determines the action to take.
  function processTicket() {
    // Run on the hostname.
    $this->log("Starting processTicket() using " . $this->storage['url']);
    $output_basename = "/mnt/tmp/" . get_class($this) . "-ticket-" . $this->ticket->id;

    if (file_exists("{$output_basename}.html")) {
      $this->log("File {$output_basename}.html already exists. Skipping attaching this to ticket.");
      return false;
    }

    if (!file_exists("{$output_basename}.txt")) {
      $cmd = "ahtpanic.sh";
      $cmd .= " " . $this->storage['url'];
      $cmd .= " --summary-file={$output_basename}-summary.txt";
      $cmd .= " 2>&1 >{$output_basename}.txt";

      // Execute with a timeout of 300.
      $command_result = $this->runCommandWithTimeout($cmd, 30);

      if ($command_result['timed_out']) {
        $this->log("Command timed out!");
        return FALSE;
      }
    }

    if (exec("grep -c 'You do not have an open connection to the server' {$output_basename}.txt") != '0') {
      $this->log("Could not connect to Bastion. Aborting!");
      // Clean up both output files for a "second chance"
      $this->removeOutputFiles($output_basename);
      return FALSE;
    }

    if (exec("egrep -c 'an application with that name exists on multiple realms' {$output_basename}.txt") != '0') {
      $this->log("Command wasn't able to figure out the realm/stage for the site. Aborting!");
      return FALSE;
    }

    if (exec("fgrep -c '^C' {$output_basename}.txt") != '0') {
      $this->log("Output of the command had ^C (breaks). Aborting!");
      // Clean up both output files for a "second chance"
      $this->removeOutputFiles($output_basename);
      return FALSE;
    }

    // Convert to HTML, with intermediate file for debugging.
    // Cutting the input avoids trying to parse huge input lines (MySQL queries, loglines, etc.)
    exec("cut -c1-2000 {$output_basename}.txt |ansi2html --bg=dark --palette=tango >{$output_basename}.html");

    if (!file_exists("{$output_basename}.html")) {
      $this->log("Could not run ansi2html. Aborting!");
      return FALSE;
    }

    // Finally, queue the "add the comment" action here.
    $comment = '**AutoPanic** ran and attached a run of command `ahtpanic.sh ' . $this->storage['url'] . '`.';
    if (isset($command_result['elapsed_time'])) {
      $comment .= ' (Took ' . $command_result['elapsed_time'] . " secs).\n";
    }
    $comment .= "\n";
    // Read in summary file.
    if (file_exists("{$output_basename}-summary.txt")) {
      $comment .= file_get_contents("{$output_basename}-summary.txt") . "\n";
    }
    // Footer.
    $comment .= "[ [leave feedback for AutoPanic](https://docs.google.com/a/acquia.com/forms/d/e/1FAIpQLSdPKAuQa-V3lEpqrSl8fala7ExJuSpHdOeLKuGRnhbnf5fO2Q/viewform?usp=pp_url&entry.516642626=" . $this->ticket->id . "&entry.64614507) | Slack [#team-support-apanic](https://acquia.slack.com/app_redirect?channel=team-support-apanic) | *\"I panic so you don't have to!\"* ] @xvr10000";
    $action = [
      'type' => "postCommentAndFile",
      'args' => [
        'comment_body' => $comment,
        'infile' => "{$output_basename}.html",
        'is_public' => 0,
      ],
    ];
    $this->queueAction($action);

    return TRUE;
  }
}
