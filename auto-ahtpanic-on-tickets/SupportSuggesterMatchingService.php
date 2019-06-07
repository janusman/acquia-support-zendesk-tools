<?php

/**
 * Match the Support Ticket Autocomplete rules (from Google Docs spreadsheet) to a given string.
 *
 * Usage:
 *   $matcher_service = new SupportSuggesterMatcherService();
 *   $matcher_service->getMatches("Are there plans to include PHP 7.1 / 7.2 in DevDesktop")
 *
 *  Returns:
 *   Array
 * (
 *    [0] => Array
 *        (
 *            [match_string] => dev *desktop .*PHP 7|PHP 7.*dev *desktop
 *            [title] => PHP 7 support available in latest Acquia Dev Desktop
 *            [url] => https://dev.acquia.com/downloads
 *            [match_mode] => regex
 *            [status] => released
 *         )
 *  )
 *
 */
 
class SupportSuggesterMatcherService {

  protected $mappings = [];
  protected $status_filter = ['released'];
  protected $caching_enabled = true;
  
  function __construct(
    $status_filter = ["released"],
    $caching_enabled = true
  ) {
    $this->status_filter = $status_filter;
    $this->caching_enabled = $caching_enabled;
    $this->mappings = $this->downloadMappings();
  }
  
  // Get the rules from Google or use a local copy (if not stale).
  function downloadMappings() {
    $source_url = 'https://docs.google.com/spreadsheets/d/e/2PACX-1vROYRO7yLj6h_cZ3pzOH46sRLXxL3ZLrPfyOTlD23LhfIncguJ7QYjR5DuRd0IiBrgacmtNjC6nqyXs/pub?output=tsv';
    $tmp_file = sys_get_temp_dir() . '/suggester_mappings_cache.txt';
    $stale_time = $this->caching_enabled ? 300 : -1;

    $result = false;
    if (file_exists($tmp_file)) {
      $cached = @unserialize(file_get_contents($tmp_file));
      if ($cached && is_array($cached)) {
        // Only accept non-stale data
        if ($cached['time'] > time()-$stale_time) {
          $result = $cached['result'];
        }
      }
    }

    // If still no data, fetch with a web request and cache it locally.
    if (!$result) {
      $result = file_get_contents($source_url);

      if (!$result) {
        echo '_acquia_support_suggester_get_mappings(): Could not fetch data from Google Doc' . PHP_EOL;
        return FALSE;
      }

      // Write to cache.
      $cached = [
        'time' => time(),
        'result' => $result
      ];
      file_put_contents($tmp_file, serialize($cached));
    }

    // Process the results and filter by the desired status.
    $data = [];
    $rows = explode("\n", $result);
    foreach ($rows as $row_num => $row_data) {
      @list($status, , $match_mode, $match_string, $title, $url) = explode("\t", trim($row_data));
      
      // Filter by status.
      if (!in_array(trim($status), $this->status_filter)) {
        continue;
      }
      
      // Send into data array.
      $data[] = [
        'match_string' => $match_string,
        'title' => $title,
        'url' => $url,
        'match_mode' => $match_mode,
        'status' => $status,
      ];
    }

    #echo "Loaded " . count($data) . " rules for matching\n";
    return $data;
  }
  
  // Test all rules against string and try to get matches
  function getMatches($haystack) {
    $matches = [];
    foreach ($this->mappings as $rule) {
      $match = false;
      switch($rule['match_mode']) {
        case 'direct':
          $match = (stripos($haystack,  $rule['match_string']) !== FALSE);
          break;
        case 'regex':
          $regex = "%" . str_replace('%', '\%', $rule['match_string']) . "%i";
          $match = preg_match_all($regex, $haystack, $dummy);
          break;
      }
      if ($match) {
        $matches[] = $rule;
        #echo "MATCH FOUND!" . print_r($rule, TRUE) . PHP_EOL;
      }
    }
    return $matches;
  }

}

#$x = new SupportSuggesterMatcherService();
#print_r($x->getMatches("Are there plans to include PHP 7.1 / 7.2 in DevDesktop"));
