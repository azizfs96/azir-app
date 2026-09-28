<?php

namespace App\Http\Controllers;

use Illuminate\Foundation\Auth\Access\AuthorizesRequests;

/**
 * Base controller.
 *
 * AuthorizesRequests is what makes $this->authorize() available — layer 3 of
 * tenant isolation (ARCHITECTURE.md §4). A merchant controller that forgets to
 * call it still cannot leak data thanks to the global scope, but every write
 * path should call it explicitly.
 */
abstract class Controller
{
    use AuthorizesRequests;
}
